#pragma once

#include <QObject>
#include <QString>
#include <QImage>
#include <QByteArray>
#include <QAudioFormat>
#include <QtQml/qqmlregistration.h>
#include <QVideoSink>
#include <QVideoFrame>

#include "LibAV/worker_encoder.h"

class QThread;
class QAudioSource;
class QIODevice;

// QML-facing controller that connects QML Camera/VideoOutput and microphone
// to the LibAv encoder (EncoderRTMP via WorkerEncoder).
class StreamingController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool streaming READ streaming NOTIFY streamingChanged)
    Q_PROPERTY(QString streamUrl READ streamUrl WRITE setStreamUrl NOTIFY streamUrlChanged)

    Q_PROPERTY(int videoBitrateKbps READ videoBitrateKbps
               WRITE setVideoBitrateKbps
               NOTIFY videoSettingsChanged)

    Q_PROPERTY(int fps READ fps
               WRITE setFps
               NOTIFY videoSettingsChanged)

    Q_PROPERTY(QVideoSink *videoSink READ videoSink
               WRITE setVideoSink
               NOTIFY videoSinkChanged)

    Q_PROPERTY(bool audioEnabled READ audioEnabled
               WRITE setAudioEnabled
               NOTIFY audioSettingsChanged)

    Q_PROPERTY(int audioBitrateKbps READ audioBitrateKbps
               WRITE setAudioBitrateKbps
               NOTIFY audioSettingsChanged)

public:
    explicit StreamingController(QObject *parent = nullptr);
    ~StreamingController() override;

    // State
    bool streaming() const { return m_streaming; }

    // URL
    QString streamUrl() const { return m_streamUrl; }
    void setStreamUrl(const QString &url);

    // Video settings
    int  videoBitrateKbps() const { return m_videoBitrateKbps; }
    void setVideoBitrateKbps(int kbps);

    int  fps() const { return m_fps; }
    void setFps(int fps);

    // Video sink (from QML)
    QVideoSink *videoSink() const { return m_videoSink; }
    void setVideoSink(QVideoSink *sink);

    // Audio settings
    bool audioEnabled() const { return m_audioEnabled; }
    void setAudioEnabled(bool enabled);

    int  audioBitrateKbps() const { return m_audioBitrateKbps; }
    void setAudioBitrateKbps(int kbps);

    // Control from QML
    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();

signals:
    // Properties
    void streamingChanged();
    void streamUrlChanged();
    void videoSettingsChanged();
    void audioSettingsChanged();
    void videoSinkChanged();

    // To worker thread
    void requestOpen(const QString &url,
                     int width, int height, int fps,
                     int videoBitrateKbps,
                     int audioSampleRate, int audioChannels, int audioBitrateKbps);
    void requestClose();
    void videoFrameReady(const QImage &image);
    void audioPcmReady(const QByteArray &pcm);

private slots:
    void onVideoFrameChanged(const QVideoFrame &frame);
    void onAudioReadyRead();

private:
    void ensureWorker();
    void startAudio();
    void stopAudio();

    // State
    bool    m_streaming        = false;
    QString m_streamUrl;

    // Video configuration
    int m_videoBitrateKbps = 2500;
    int m_fps              = 30;

    // Audio configuration
    bool         m_audioEnabled     = true;
    int          m_audioBitrateKbps = 96000;
    QAudioFormat m_audioFormat;

    // Video source (sink) from QML
    QVideoSink *m_videoSink = nullptr;

    // Worker thread and encoder worker
    QThread       *m_workerThread  = nullptr;
    WorkerEncoder *m_worker        = nullptr;
    bool           m_encoderOpened = false;

    // Audio capture
    QAudioSource *m_audioSource = nullptr;
    QIODevice    *m_audioDevice = nullptr;
};