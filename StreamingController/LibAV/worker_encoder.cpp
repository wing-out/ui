#include "worker_encoder.h"

WorkerEncoder::WorkerEncoder(QObject *parent) : QObject(parent) {}

void WorkerEncoder::setEncoderFactory(const EncoderFactory &factory) {
  m_factory = factory;
}

void WorkerEncoder::open(const QString &url, int width, int height, int fps,
                         int videoBitrateKbps, int audioSampleRate,
                         int audioChannels, int audioBitrateKbps) {
  if (!m_factory) {
    emit opened(false, url);
    return;
  }

  if (!m_encoder) {
    m_encoder = m_factory();
  }

  if (!m_encoder) {
    emit opened(false, url);
    return;
  }

  if (m_opened) {
    m_encoder->close();
    m_opened = false;
  }

  VideoParams v;
  v.width = width;
  v.height = height;
  v.fps = fps;
  v.bitrateKbps = videoBitrateKbps;

  AudioParams a;
  a.sampleRate = audioSampleRate;
  a.channels = audioChannels;
  a.bitrateKbps = audioBitrateKbps;

  bool ok = m_encoder->open(url, v, a);
  m_opened = ok;

  emit opened(ok, url);
}

void WorkerEncoder::close() {
  if (m_encoder && m_opened) {
    m_encoder->close();
  }

  m_opened = false;
  emit stopped();
}

void WorkerEncoder::encodeVideoFrame(const QImage &image) {
  if (!m_opened || !m_encoder)
    return;
  m_encoder->encodeVideoFrame(image);
}

void WorkerEncoder::encodeAudioPcm(const QByteArray &pcm) {
  if (!m_opened || !m_encoder)
    return;
  m_encoder->encodeAudioSamples(pcm);
}