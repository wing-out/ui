#pragma once

#include <QByteArray>
#include <QImage>
#include <QString>

// Video encoding parameters
struct VideoParams {
  int width = 0;
  int height = 0;
  int fps = 30;
  int bitrateKbps = 2500;
};

// Audio encoding parameters
// If any of these are <= 0, audio is treated as "disabled".
struct AudioParams {
  int sampleRate = 0;  // Hz
  int channels = 0;    // 1, 2, ...
  int bitrateKbps = 0; // kbps
};

// Generic LibAV-based encoder interface.
// Video: QImage (RGBA).
// Audio: PCM S16 interleaved (sampleRate/channels as in LibAvAudioParams).
class Encoder {
public:
  virtual ~Encoder() = default;

  virtual bool open(const QString &url, const VideoParams &video,
                    const AudioParams &audio) = 0;

  virtual void close() = 0;
  virtual bool isOpen() const = 0;

  virtual bool encodeVideoFrame(const QImage &image) = 0;
  virtual bool encodeAudioSamples(const QByteArray &pcm) = 0;
};