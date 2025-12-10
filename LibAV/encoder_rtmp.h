#pragma once

#include "encoder.h"

struct AVFormatContext;
struct AVCodecContext;
struct AVStream;
struct AVFrame;
struct SwsContext;
struct SwrContext;

// RTMP FLV muxer/encoder (H.264 + optional AAC) using modern LibAV/FFmpeg API.
class EncoderRTMP : public Encoder {
public:
  EncoderRTMP();
  ~EncoderRTMP() override;

  bool open(const QString &url, const VideoParams &video,
            const AudioParams &audio) override;

  void close() override;
  bool isOpen() const override { return m_opened; }

  bool encodeVideoFrame(const QImage &image) override;
  // PCM S16 interleaved (sampleRate/channels from LibAvAudioParams)
  bool encodeAudioSamples(const QByteArray &pcm) override;

private:
  bool initContext(const QString &url, const VideoParams &video,
                   const AudioParams &audio);

  bool initVideoStream(const VideoParams &video);
  bool initAudioStream(const AudioParams &audio);

  bool writeVideoFrame(const QImage &image);
  bool drainAudioBuffer();

  bool flushEncoder(AVCodecContext *ctx, AVStream *stream);
  void cleanup();

  // container
  AVFormatContext *m_formatCtx = nullptr;
  bool m_opened = false;

  // video
  AVCodecContext *m_videoCodecCtx = nullptr;
  AVStream *m_videoStream = nullptr;
  AVFrame *m_videoFrame = nullptr;
  SwsContext *m_swsCtx = nullptr;
  int m_width = 0;
  int m_height = 0;
  int m_fps = 0;
  int64_t m_videoPts = 0;

  // audio
  AVCodecContext *m_audioCodecCtx = nullptr;
  AVStream *m_audioStream = nullptr;
  AVFrame *m_audioFrame = nullptr;
  SwrContext *m_swrCtx = nullptr;
  int m_audioSampleRate = 0;
  int m_audioChannels = 0;
  int m_audioFrameSize = 0; // nb_samples
  int64_t m_audioPts = 0;
  QByteArray m_audioBuffer; // raw PCM S16 interleaved
};