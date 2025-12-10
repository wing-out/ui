
#include <QVideoSink>
#include <QVideoFrame>
#include <QThread>
#include <QDebug>
#include <QMediaDevices>
#include <QAudioSource>
#include <QAudioDevice>
#include <QIODevice>

#include "streaming_controller.h"
#include "LibAV/encoder_rtmp.h"

// ---------------------------------------------------------------------
// ctor / dtor
// ---------------------------------------------------------------------

StreamingController::StreamingController(QObject *parent)
    : QObject(parent)
{
    // Configure default audio format (S16 interleaved) from default input
    QAudioDevice inputDevice = QMediaDevices::defaultAudioInput();
    if (!inputDevice.isNull()) {
        QAudioFormat preferred = inputDevice.preferredFormat();
        preferred.setSampleFormat(QAudioFormat::Int16);

        if (inputDevice.isFormatSupported(preferred)) {
            m_audioFormat = preferred;
        } else {
            m_audioFormat = inputDevice.preferredFormat();
        }
    }

    if (m_audioFormat.sampleRate() <= 0 ||
        m_audioFormat.channelCount() <= 0) {
        m_audioEnabled = false;
        qWarning() << "StreamingController: no valid audio input, disabling audio";
    }
}

StreamingController::~StreamingController()
{
    stop();

    if (m_workerThread) {
        emit requestClose();
        m_workerThread->quit();
        m_workerThread->wait();
        m_workerThread = nullptr;
        m_worker       = nullptr;
    }

    stopAudio();
}

// ---------------------------------------------------------------------
// Property setters
// ---------------------------------------------------------------------

void StreamingController::setStreamUrl(const QString &url)
{
    if (m_streamUrl == url)
        return;
    m_streamUrl = url;
    emit streamUrlChanged();
}

void StreamingController::setVideoBitrateKbps(int kbps)
{
    if (kbps <= 0)
        kbps = 1;
    if (m_videoBitrateKbps == kbps)
        return;
    m_videoBitrateKbps = kbps;
    emit videoSettingsChanged();
}

void StreamingController::setFps(int fps)
{
    if (fps <= 0)
        fps = 1;
    if (m_fps == fps)
        return;
    m_fps = fps;
    emit videoSettingsChanged();
}

void StreamingController::setVideoSink(QVideoSink *sink)
{
    if (m_videoSink == sink)
        return;

    if (m_videoSink) {
        disconnect(m_videoSink, &QVideoSink::videoFrameChanged,
                   this, &StreamingController::onVideoFrameChanged);
    }

    m_videoSink = sink;

    if (m_videoSink) {
        connect(m_videoSink, &QVideoSink::videoFrameChanged,
                this, &StreamingController::onVideoFrameChanged);
    }

    emit videoSinkChanged();
}

void StreamingController::setAudioEnabled(bool enabled)
{
    if (m_audioEnabled == enabled)
        return;

    m_audioEnabled = enabled;

    if (!m_audioEnabled) {
        stopAudio();
    } else if (m_streaming) {
        startAudio();
    }

    emit audioSettingsChanged();
}

void StreamingController::setAudioBitrateKbps(int kbps)
{
    if (kbps <= 0)
        kbps = 1;

    if (m_audioBitrateKbps == kbps)
        return;

    m_audioBitrateKbps = kbps;
    emit audioSettingsChanged();
}

// ---------------------------------------------------------------------
// Public control API
// ---------------------------------------------------------------------

void StreamingController::start()
{
    if (m_streaming)
        return;

    if (m_streamUrl.isEmpty()) {
        qWarning() << "StreamingController: streamUrl is empty, cannot start";
        return;
    }

    m_streaming     = true;
    m_encoderOpened = false;

    emit streamingChanged();

    ensureWorker();
    startAudio();
}

void StreamingController::stop()
{
    if (!m_streaming && !m_encoderOpened)
        return;

    m_streaming     = false;
    m_encoderOpened = false;

    emit streamingChanged();

    stopAudio();
    emit requestClose();
}

// ---------------------------------------------------------------------
// Worker setup
// ---------------------------------------------------------------------

void StreamingController::ensureWorker()
{
    if (m_worker)
        return;

    m_workerThread = new QThread(this);
    m_worker       = new WorkerEncoder;

    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::finished,
            m_worker, &QObject::deleteLater);

    // Set LibAv encoder factory (H.264 + AAC RTMP)
    m_worker->setEncoderFactory([]() -> std::unique_ptr<Encoder> {
        return std::unique_ptr<Encoder>(new EncoderRTMP);
    });

    // Cross-thread connections
    connect(this, &StreamingController::requestOpen,
            m_worker, &WorkerEncoder::open,
            Qt::QueuedConnection);

    connect(this, &StreamingController::requestClose,
            m_worker, &WorkerEncoder::close,
            Qt::QueuedConnection);

    connect(this, &StreamingController::videoFrameReady,
            m_worker, &WorkerEncoder::encodeVideoFrame,
            Qt::QueuedConnection);

    connect(this, &StreamingController::audioPcmReady,
            m_worker, &WorkerEncoder::encodeAudioPcm,
            Qt::QueuedConnection);

    // Optional feedback
    connect(m_worker, &WorkerEncoder::opened,
            this, [this](bool ok, const QString &url) {
                if (!ok) {
                    qWarning() << "StreamingController: encoder failed to open for" << url;
                    m_encoderOpened = false;
                }
            });

    connect(m_worker, &WorkerEncoder::stopped,
            this, [this]() {
                m_encoderOpened = false;
            });

    m_workerThread->start();
}

// ---------------------------------------------------------------------
// Video path (QVideoSink → QImage → worker)
// ---------------------------------------------------------------------

void StreamingController::onVideoFrameChanged(const QVideoFrame &frame)
{
    if (!m_streaming)
        return;
    if (!frame.isValid())
        return;

    QVideoFrame copyFrame(frame);
    QImage img = copyFrame.toImage();
    if (img.isNull())
        return;

    // First frame: open encoder with discovered resolution
    if (!m_encoderOpened) {
        ensureWorker();
        if (!m_worker)
            return;

        const int width  = img.width();
        const int height = img.height();

        int audioSampleRate = 0;
        int audioChannels   = 0;
        int audioBitrate    = 0;

        if (m_audioEnabled &&
            m_audioFormat.sampleRate() > 0 &&
            m_audioFormat.channelCount() > 0 &&
            m_audioBitrateKbps > 0) {

            audioSampleRate = m_audioFormat.sampleRate();
            audioChannels   = m_audioFormat.channelCount();
            audioBitrate    = m_audioBitrateKbps;
        }

        emit requestOpen(m_streamUrl,
                         width, height, m_fps,
                         m_videoBitrateKbps,
                         audioSampleRate, audioChannels, audioBitrate);

        m_encoderOpened = true;
    }

    emit videoFrameReady(img);
}

// ---------------------------------------------------------------------
// Audio path (QAudioSource → PCM S16 → worker)
// ---------------------------------------------------------------------

void StreamingController::startAudio()
{
    if (!m_audioEnabled)
        return;
    if (m_audioSource)
        return;

    QAudioDevice inputDevice = QMediaDevices::defaultAudioInput();
    if (inputDevice.isNull()) {
        qWarning() << "StreamingController: no default audio input, disabling audio";
        m_audioEnabled = false;
        emit audioSettingsChanged();
        return;
    }

    if (!inputDevice.isFormatSupported(m_audioFormat)) {
        qWarning() << "StreamingController: requested audio format not supported, using preferred";
        m_audioFormat = inputDevice.preferredFormat();
    }

    m_audioSource = new QAudioSource(inputDevice, m_audioFormat, this);
    m_audioDevice = m_audioSource->start();

    if (!m_audioDevice) {
        qWarning() << "StreamingController: failed to start QAudioSource";
        delete m_audioSource;
        m_audioSource = nullptr;
        m_audioEnabled = false;
        emit audioSettingsChanged();
        return;
    }

    connect(m_audioDevice, &QIODevice::readyRead,
            this, &StreamingController::onAudioReadyRead);
}

void StreamingController::stopAudio()
{
    if (m_audioDevice) {
        disconnect(m_audioDevice, &QIODevice::readyRead,
                   this, &StreamingController::onAudioReadyRead);
        m_audioDevice = nullptr;
    }

    if (m_audioSource) {
        m_audioSource->stop();
        m_audioSource->deleteLater();
        m_audioSource = nullptr;
    }
}

void StreamingController::onAudioReadyRead()
{
    if (!m_audioDevice)
        return;

    QByteArray data = m_audioDevice->readAll();
    if (data.isEmpty())
        return;

    // Drop audio until encoder is opened
    if (!m_streaming || !m_encoderOpened)
        return;

    emit audioPcmReady(data);
}