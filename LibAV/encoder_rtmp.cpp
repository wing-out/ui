#include "encoder_rtmp.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
}

#include <QByteArray>
#include <QDebug>

// ---------------------------------------------------------------------
// ctor / dtor
// ---------------------------------------------------------------------

EncoderRTMP::EncoderRTMP() {
  static bool networkInit = false;
  if (!networkInit) {
    avformat_network_init();
    networkInit = true;
  }
}

EncoderRTMP::~EncoderRTMP() { close(); }

// ---------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------

bool EncoderRTMP::open(const QString &url, const VideoParams &video,
                       const AudioParams &audio) {
  close(); // reset any previous state

  m_width = video.width;
  m_height = video.height;
  m_fps = video.fps;
  m_videoPts = 0;
  m_audioPts = 0;
  m_audioBuffer.clear();

  if (!initContext(url, video, audio)) {
    cleanup();
    return false;
  }

  m_opened = true;
  return true;
}

void EncoderRTMP::close() {
  if (m_opened) {
    // Flush video
    if (m_videoCodecCtx && m_videoStream) {
      int ret = avcodec_send_frame(m_videoCodecCtx, nullptr);
      if (ret >= 0 || ret == AVERROR_EOF) {
        flushEncoder(m_videoCodecCtx, m_videoStream);
      }
    }

    // Flush audio
    if (m_audioCodecCtx && m_audioStream) {
      int ret = avcodec_send_frame(m_audioCodecCtx, nullptr);
      if (ret >= 0 || ret == AVERROR_EOF) {
        flushEncoder(m_audioCodecCtx, m_audioStream);
      }
    }

    if (m_formatCtx) {
      int tret = av_write_trailer(m_formatCtx);
      if (tret < 0) {
        qWarning() << "RtmpEncoder: av_write_trailer failed:" << tret;
      }
    }
  }

  cleanup();
  m_opened = false;
}

bool EncoderRTMP::encodeVideoFrame(const QImage &image) {
  if (!m_opened || !m_videoCodecCtx || !m_videoFrame || !m_swsCtx)
    return false;

  return writeVideoFrame(image);
}

bool EncoderRTMP::encodeAudioSamples(const QByteArray &pcm) {
  if (!m_opened || !m_audioCodecCtx || !m_audioFrame || !m_swrCtx)
    return false;
  if (pcm.isEmpty())
    return true;

  m_audioBuffer.append(pcm);
  return drainAudioBuffer();
}

// ---------------------------------------------------------------------
// Internal initialization
// ---------------------------------------------------------------------

bool EncoderRTMP::initContext(const QString &url, const VideoParams &video,
                              const AudioParams &audio) {
  QByteArray urlBytes = url.toUtf8();
  const char *cUrl = urlBytes.constData();

  // Allocate output context for FLV (RTMP)
  int ret = avformat_alloc_output_context2(&m_formatCtx, nullptr, "flv", cUrl);
  if (ret < 0 || !m_formatCtx) {
    qWarning() << "RtmpEncoder: avformat_alloc_output_context2 failed:" << ret;
    return false;
  }

  if (!initVideoStream(video))
    return false;

  if (!initAudioStream(audio))
    return false;

  // Open IO if needed
  if (!(m_formatCtx->oformat->flags & AVFMT_NOFILE)) {
    ret = avio_open(&m_formatCtx->pb, cUrl, AVIO_FLAG_WRITE);
    if (ret < 0) {
      qWarning() << "RtmpEncoder: avio_open failed:" << ret;
      return false;
    }
  }

  // Write container header
  ret = avformat_write_header(m_formatCtx, nullptr);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avformat_write_header failed:" << ret;
    return false;
  }

  return true;
}

bool EncoderRTMP::initVideoStream(const VideoParams &video) {
  const AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_H264);
  if (!codec) {
    qWarning() << "RtmpEncoder: H.264 encoder not found";
    return false;
  }

  // Create stream
  m_videoStream = avformat_new_stream(m_formatCtx, nullptr);
  if (!m_videoStream) {
    qWarning() << "RtmpEncoder: failed to create video stream";
    return false;
  }

  m_videoCodecCtx = avcodec_alloc_context3(codec);
  if (!m_videoCodecCtx) {
    qWarning() << "RtmpEncoder: failed to alloc video codec context";
    return false;
  }

  m_videoCodecCtx->codec_id = codec->id;
  m_videoCodecCtx->codec_type = AVMEDIA_TYPE_VIDEO;
  m_videoCodecCtx->width = video.width;
  m_videoCodecCtx->height = video.height;
  m_videoCodecCtx->pix_fmt = AV_PIX_FMT_YUV420P;
  m_videoCodecCtx->time_base = AVRational{1, video.fps};
  m_videoCodecCtx->framerate = AVRational{video.fps, 1};
  m_videoCodecCtx->bit_rate = static_cast<int64_t>(video.bitrateKbps) * 1000;

  // Low-latency H.264 settings
  av_opt_set(m_videoCodecCtx->priv_data, "preset", "veryfast", 0);
  av_opt_set(m_videoCodecCtx->priv_data, "tune", "zerolatency", 0);

  // Global header if container requires it
  if (m_formatCtx->oformat->flags & AVFMT_GLOBALHEADER)
    m_videoCodecCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

  int ret = avcodec_open2(m_videoCodecCtx, codec, nullptr);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avcodec_open2(video) failed:" << ret;
    return false;
  }

  ret =
      avcodec_parameters_from_context(m_videoStream->codecpar, m_videoCodecCtx);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avcodec_parameters_from_context(video) failed:"
               << ret;
    return false;
  }

  m_videoStream->time_base = m_videoCodecCtx->time_base;

  // Allocate reusable video frame
  m_videoFrame = av_frame_alloc();
  if (!m_videoFrame) {
    qWarning() << "RtmpEncoder: av_frame_alloc(video) failed";
    return false;
  }

  m_videoFrame->format = m_videoCodecCtx->pix_fmt;
  m_videoFrame->width = m_videoCodecCtx->width;
  m_videoFrame->height = m_videoCodecCtx->height;

  ret = av_frame_get_buffer(m_videoFrame, 32);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: av_frame_get_buffer(video) failed:" << ret;
    return false;
  }

  // RGBA (QImage) -> YUV420P
  m_swsCtx = sws_getContext(m_videoCodecCtx->width, m_videoCodecCtx->height,
                            AV_PIX_FMT_RGBA, m_videoCodecCtx->width,
                            m_videoCodecCtx->height, m_videoCodecCtx->pix_fmt,
                            SWS_BILINEAR, nullptr, nullptr, nullptr);

  if (!m_swsCtx) {
    qWarning() << "RtmpEncoder: sws_getContext failed";
    return false;
  }

  return true;
}

bool EncoderRTMP::initAudioStream(const AudioParams &audio) {
  // Audio disabled?
  if (audio.sampleRate <= 0 || audio.channels <= 0 || audio.bitrateKbps <= 0)
    return true;

  m_audioSampleRate = audio.sampleRate;
  m_audioChannels = audio.channels;
  m_audioPts = 0;

  const AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
  if (!codec) {
    qWarning() << "RtmpEncoder: AAC encoder not found";
    return false;
  }

  m_audioStream = avformat_new_stream(m_formatCtx, nullptr);
  if (!m_audioStream) {
    qWarning() << "RtmpEncoder: failed to create audio stream";
    return false;
  }

  m_audioCodecCtx = avcodec_alloc_context3(codec);
  if (!m_audioCodecCtx) {
    qWarning() << "RtmpEncoder: failed to alloc audio codec context";
    return false;
  }

  m_audioCodecCtx->codec_type = AVMEDIA_TYPE_AUDIO;
  m_audioCodecCtx->codec_id = codec->id;
  m_audioCodecCtx->sample_rate = m_audioSampleRate;
  m_audioCodecCtx->bit_rate = static_cast<int64_t>(audio.bitrateKbps) * 1000;
  m_audioCodecCtx->time_base = AVRational{1, m_audioSampleRate};

  // Channel layout via new API
  AVChannelLayout layout;
  av_channel_layout_default(&layout, m_audioChannels);
  m_audioCodecCtx->ch_layout = layout;

  // Use a common AAC sample format (no deprecated sample_fmts access)
  m_audioCodecCtx->sample_fmt =
      AV_SAMPLE_FMT_FLTP; // typical AAC encoder format

  if (m_formatCtx->oformat->flags & AVFMT_GLOBALHEADER)
    m_audioCodecCtx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

  // Allow experimental AAC if needed
  m_audioCodecCtx->strict_std_compliance = FF_COMPLIANCE_EXPERIMENTAL;

  int ret = avcodec_open2(m_audioCodecCtx, codec, nullptr);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avcodec_open2(audio) failed:" << ret;
    return false;
  }

  ret =
      avcodec_parameters_from_context(m_audioStream->codecpar, m_audioCodecCtx);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avcodec_parameters_from_context(audio) failed:"
               << ret;
    return false;
  }

  m_audioStream->time_base = m_audioCodecCtx->time_base;

  // Allocate reusable audio frame
  m_audioFrame = av_frame_alloc();
  if (!m_audioFrame) {
    qWarning() << "RtmpEncoder: av_frame_alloc(audio) failed";
    return false;
  }

  m_audioFrameSize = m_audioCodecCtx->frame_size;
  if (m_audioFrameSize <= 0) {
    // Fallback if codec doesn't set a fixed frame size
    m_audioFrameSize = m_audioSampleRate / 50; // ~20ms
  }

  m_audioFrame->nb_samples = m_audioFrameSize;
  m_audioFrame->format = m_audioCodecCtx->sample_fmt;
  m_audioFrame->sample_rate = m_audioCodecCtx->sample_rate;
  m_audioFrame->ch_layout = m_audioCodecCtx->ch_layout;

  ret = av_frame_get_buffer(m_audioFrame, 0);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: av_frame_get_buffer(audio) failed:" << ret;
    return false;
  }

  // Resampler: input = S16 interleaved (from QAudioSource), output = codec
  // format
  AVChannelLayout inLayout;
  av_channel_layout_default(&inLayout, m_audioChannels);

  ret = swr_alloc_set_opts2(&m_swrCtx, &m_audioCodecCtx->ch_layout,
                            m_audioCodecCtx->sample_fmt,
                            m_audioCodecCtx->sample_rate, &inLayout,
                            AV_SAMPLE_FMT_S16, m_audioSampleRate, 0, nullptr);
  if (ret < 0 || !m_swrCtx) {
    qWarning() << "RtmpEncoder: swr_alloc_set_opts2 failed:" << ret;
    return false;
  }

  ret = swr_init(m_swrCtx);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: swr_init failed:" << ret;
    return false;
  }

  return true;
}

// ---------------------------------------------------------------------
// Video path
// ---------------------------------------------------------------------

bool EncoderRTMP::writeVideoFrame(const QImage &srcImage) {
  if (srcImage.isNull())
    return false;

  QImage img = srcImage;
  if (img.format() != QImage::Format_RGBA8888) {
    img = img.convertToFormat(QImage::Format_RGBA8888);
  }

  if (av_frame_make_writable(m_videoFrame) < 0) {
    qWarning() << "RtmpEncoder: av_frame_make_writable(video) failed";
    return false;
  }

  const uint8_t *inData[4] = {img.bits(), nullptr, nullptr, nullptr};
  const int stride = static_cast<int>(img.bytesPerLine());
  int inLinesize[4] = {stride, 0, 0, 0};

  sws_scale(m_swsCtx, inData, inLinesize, 0, m_height, m_videoFrame->data,
            m_videoFrame->linesize);

  m_videoFrame->pts = m_videoPts++;

  int ret = avcodec_send_frame(m_videoCodecCtx, m_videoFrame);
  if (ret < 0) {
    qWarning() << "RtmpEncoder: avcodec_send_frame(video) failed:" << ret;
    return false;
  }

  AVPacket *pkt = av_packet_alloc();
  if (!pkt) {
    qWarning() << "RtmpEncoder: av_packet_alloc(video) failed";
    return false;
  }

  while (true) {
    ret = avcodec_receive_packet(m_videoCodecCtx, pkt);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
      break;
    if (ret < 0) {
      qWarning() << "RtmpEncoder: avcodec_receive_packet(video) failed:" << ret;
      av_packet_unref(pkt);
      break;
    }

    av_packet_rescale_ts(pkt, m_videoCodecCtx->time_base,
                         m_videoStream->time_base);
    pkt->stream_index = m_videoStream->index;

    int wret = av_interleaved_write_frame(m_formatCtx, pkt);
    if (wret < 0) {
      qWarning() << "RtmpEncoder: av_interleaved_write_frame(video) failed:"
                 << wret;
      av_packet_unref(pkt);
      break;
    }

    av_packet_unref(pkt);
  }

  av_packet_free(&pkt);
  return true;
}

// ---------------------------------------------------------------------
// Audio path
// ---------------------------------------------------------------------

bool EncoderRTMP::drainAudioBuffer() {
  if (!m_audioCodecCtx || !m_audioFrame || !m_swrCtx)
    return false;

  const int channels = m_audioCodecCtx->ch_layout.nb_channels;
  const int bytesPerSample = static_cast<int>(sizeof(int16_t)) * channels;
  const int frameBytes = m_audioFrameSize * bytesPerSample;

  while (m_audioBuffer.size() >= frameBytes) {
    const uint8_t *inputPtr =
        reinterpret_cast<const uint8_t *>(m_audioBuffer.constData());

    const uint8_t *inData[1] = {inputPtr};

    if (av_frame_make_writable(m_audioFrame) < 0) {
      qWarning() << "RtmpEncoder: av_frame_make_writable(audio) failed";
      return false;
    }

    int ret = swr_convert(m_swrCtx, m_audioFrame->data, m_audioFrameSize,
                          inData, m_audioFrameSize);
    if (ret < 0) {
      qWarning() << "RtmpEncoder: swr_convert failed:" << ret;
      return false;
    }

    m_audioFrame->nb_samples = ret;
    m_audioFrame->pts = m_audioPts;
    m_audioPts += ret;

    ret = avcodec_send_frame(m_audioCodecCtx, m_audioFrame);
    if (ret < 0) {
      qWarning() << "RtmpEncoder: avcodec_send_frame(audio) failed:" << ret;
      return false;
    }

    AVPacket *pkt = av_packet_alloc();
    if (!pkt) {
      qWarning() << "RtmpEncoder: av_packet_alloc(audio) failed";
      return false;
    }

    while (true) {
      ret = avcodec_receive_packet(m_audioCodecCtx, pkt);
      if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
        break;
      if (ret < 0) {
        qWarning() << "RtmpEncoder: avcodec_receive_packet(audio) failed:"
                   << ret;
        av_packet_unref(pkt);
        break;
      }

      av_packet_rescale_ts(pkt, m_audioCodecCtx->time_base,
                           m_audioStream->time_base);
      pkt->stream_index = m_audioStream->index;

      int wret = av_interleaved_write_frame(m_formatCtx, pkt);
      if (wret < 0) {
        qWarning() << "RtmpEncoder: av_interleaved_write_frame(audio) failed:"
                   << wret;
        av_packet_unref(pkt);
        break;
      }

      av_packet_unref(pkt);
    }

    av_packet_free(&pkt);

    // Drop consumed PCM
    m_audioBuffer.remove(0, frameBytes);
  }

  return true;
}

// ---------------------------------------------------------------------
// Flush / cleanup
// ---------------------------------------------------------------------

bool EncoderRTMP::flushEncoder(AVCodecContext *ctx, AVStream *stream) {
  if (!ctx || !stream)
    return true;

  AVPacket *pkt = av_packet_alloc();
  if (!pkt) {
    qWarning() << "RtmpEncoder: av_packet_alloc(flush) failed";
    return false;
  }

  while (true) {
    int ret = avcodec_receive_packet(ctx, pkt);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
      break;
    if (ret < 0) {
      qWarning() << "RtmpEncoder: avcodec_receive_packet(flush) failed:" << ret;
      av_packet_unref(pkt);
      break;
    }

    av_packet_rescale_ts(pkt, ctx->time_base, stream->time_base);
    pkt->stream_index = stream->index;

    int wret = av_interleaved_write_frame(m_formatCtx, pkt);
    if (wret < 0) {
      qWarning() << "RtmpEncoder: av_interleaved_write_frame(flush) failed:"
                 << wret;
      av_packet_unref(pkt);
      break;
    }

    av_packet_unref(pkt);
  }

  av_packet_free(&pkt);
  return true;
}

void EncoderRTMP::cleanup() {
  if (m_swsCtx) {
    sws_freeContext(m_swsCtx);
    m_swsCtx = nullptr;
  }

  if (m_videoFrame) {
    av_frame_free(&m_videoFrame);
    m_videoFrame = nullptr;
  }

  if (m_videoCodecCtx) {
    avcodec_free_context(&m_videoCodecCtx);
    m_videoCodecCtx = nullptr;
  }

  if (m_swrCtx) {
    swr_free(&m_swrCtx);
    m_swrCtx = nullptr;
  }

  if (m_audioFrame) {
    av_frame_free(&m_audioFrame);
    m_audioFrame = nullptr;
  }

  if (m_audioCodecCtx) {
    avcodec_free_context(&m_audioCodecCtx);
    m_audioCodecCtx = nullptr;
  }

  if (m_formatCtx) {
    if (!(m_formatCtx->oformat->flags & AVFMT_NOFILE) && m_formatCtx->pb) {
      avio_closep(&m_formatCtx->pb);
    }
    avformat_free_context(m_formatCtx);
    m_formatCtx = nullptr;
  }

  m_audioBuffer.clear();
  m_audioSampleRate = 0;
  m_audioChannels = 0;
  m_audioFrameSize = 0;
}