#pragma once

#include <QByteArray>
#include <QImage>
#include <QObject>
#include <functional>
#include <memory>

#include "encoder.h"

class WorkerEncoder : public QObject {
  Q_OBJECT
public:
  using EncoderFactory = std::function<std::unique_ptr<Encoder>()>;

  explicit WorkerEncoder(QObject *parent = nullptr);

  void setEncoderFactory(const EncoderFactory &factory);

public slots:
  void open(const QString &url, int width, int height, int fps,
            int videoBitrateKbps, int audioSampleRate, int audioChannels,
            int audioBitrateKbps);

  void close();

  void encodeVideoFrame(const QImage &image);
  void encodeAudioPcm(const QByteArray &pcm);

signals:
  void opened(bool ok, const QString &url);
  void stopped();

private:
  EncoderFactory m_factory;
  std::unique_ptr<Encoder> m_encoder;
  bool m_opened = false;
};