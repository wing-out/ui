#pragma once

#include <QObject>
#include <QString>

#include <QtQml/qqmlregistration.h>  // QML_ELEMENT

class StreamingSettingsController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Expose the actual path to QML (for logging/debugging)
    Q_PROPERTY(QString settingsFilePath READ settingsFilePath CONSTANT)

    // Whether settings are currently “active” (file present & saved OK)
    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)

    // Camera/input settings, fully readable/writable from QML
    Q_PROPERTY(int width READ width WRITE setWidth NOTIFY widthChanged)
    Q_PROPERTY(int height READ height WRITE setHeight NOTIFY heightChanged)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)
    Q_PROPERTY(int bitrateKbps READ bitrateKbps WRITE setBitrateKbps NOTIFY bitrateKbpsChanged)
    Q_PROPERTY(QString preferredCamera READ preferredCamera WRITE setPreferredCamera NOTIFY preferredCameraChanged)

    // Codec/output settings (Codec-B). Persisted alongside camera settings in
    // streaming_settings.json. videoBitrateKbps reuses the existing
    // bitrateKbps field; the new properties cover audio + codec selection.
    Q_PROPERTY(QString missionVideoCodec READ missionVideoCodec CONSTANT)
    Q_PROPERTY(QString videoCodec READ videoCodec WRITE setVideoCodec NOTIFY videoCodecChanged)
    Q_PROPERTY(QString audioCodec READ audioCodec WRITE setAudioCodec NOTIFY audioCodecChanged)
    Q_PROPERTY(int audioSampleRate READ audioSampleRate WRITE setAudioSampleRate NOTIFY audioSampleRateChanged)
    Q_PROPERTY(int audioBitrateKbps READ audioBitrateKbps WRITE setAudioBitrateKbps NOTIFY audioBitrateKbpsChanged)
    Q_PROPERTY(int audioChannels READ audioChannels WRITE setAudioChannels NOTIFY audioChannelsChanged)
    Q_PROPERTY(int maxBitrateKbps READ maxBitrateKbps WRITE setMaxBitrateKbps NOTIFY maxBitrateKbpsChanged)

    // Output destination URL pushed to ffstream.SetOutputURL on Apply and on
    // gRPC channel reconnect. Empty string means "leave the daemon-side
    // default" (typically -f null - in the boot script).
    Q_PROPERTY(QString outputUrl READ outputUrl WRITE setOutputUrl NOTIFY outputUrlChanged)

    // Microphone selection (persisted to JSON).
    Q_PROPERTY(int preferredMicrophoneId READ preferredMicrophoneId WRITE setPreferredMicrophoneId NOTIFY preferredMicrophoneIdChanged)

    // Runtime-only: priority/num pair returned by ffstream addInput for the
    // active camera and microphone inputs. Not persisted — used by Deactivate
    // to call removeInput on the matching priority/num. -1 means "no input".
    Q_PROPERTY(int activeCameraNum READ activeCameraNum WRITE setActiveCameraNum NOTIFY activeCameraNumChanged)
    Q_PROPERTY(int activeMicrophoneNum READ activeMicrophoneNum WRITE setActiveMicrophoneNum NOTIFY activeMicrophoneNumChanged)

    // Monotonic counter incremented on every user-driven activate()/deactivate().
    // Used by the QML reconciler to discard stale getInputsInfo replies that
    // would otherwise clobber a fresh user intent (race: user taps Activate
    // while a reconcile RPC is in flight; the reply comes back saying "no
    // priority-0 inputs yet" and would flip m_active back to false). Callers
    // must capture this BEFORE dispatching the reconcile RPC and pass it
    // into setActiveFromReconciliation; mismatched epoch -> reply dropped.
    Q_PROPERTY(quint64 userIntentEpoch READ userIntentEpoch NOTIFY userIntentEpochChanged)

public:
    explicit StreamingSettingsController(QObject *parent = nullptr);

    // Activate: write current properties to file and mark active=true
    Q_INVOKABLE bool activate();

    // Deactivate: delete the file (if present) and mark active=false
    Q_INVOKABLE bool deactivate();

    // Atomically set m_active from a reconciliation pass. Use ONLY from
    // the onChannelChanged reconcile path; activate()/deactivate() are
    // the user-driven setters.
    //
    // capturedEpoch must be the userIntentEpoch sampled BEFORE the RPC was
    // dispatched. If the user has tapped Activate/Deactivate since (i.e.
    // m_userIntentEpoch advanced), the reply is treated as stale and
    // dropped — m_active is left at the user's chosen state.
    Q_INVOKABLE void setActiveFromReconciliation(bool actuallyActive, quint64 capturedEpoch);

    // Bump userIntentEpoch without flipping m_active. Used to invalidate
    // any in-flight reconcile reply BEFORE rolling back a partial activate
    // (e.g. when the microphone leg of a two-leg activation failed).
    Q_INVOKABLE void bumpUserIntentEpoch();

    quint64 userIntentEpoch() const;

    // Old-style API (still usable): save given settings & activate
    Q_INVOKABLE bool saveSettings(int width,
                                  int height,
                                  int fps,
                                  int bitrateKbps,
                                  const QString &preferredCamera);

    QString settingsFilePath() const;

    bool isActive() const;

    int width() const;
    void setWidth(int w);

    int height() const;
    void setHeight(int h);

    int fps() const;
    void setFps(int fps);

    int bitrateKbps() const;
    void setBitrateKbps(int bitrate);

    QString preferredCamera() const;
    void setPreferredCamera(const QString &camera);

    QString videoCodec() const;
    QString missionVideoCodec() const;
    void setVideoCodec(const QString &codec);

    QString audioCodec() const;
    void setAudioCodec(const QString &codec);

    int audioSampleRate() const;
    void setAudioSampleRate(int rate);

    int audioBitrateKbps() const;
    void setAudioBitrateKbps(int kbps);

    int audioChannels() const;
    void setAudioChannels(int channels);

    int maxBitrateKbps() const;
    void setMaxBitrateKbps(int kbps);

    QString outputUrl() const;
    void setOutputUrl(const QString &url);

    int preferredMicrophoneId() const;
    void setPreferredMicrophoneId(int id);

    int activeCameraNum() const;
    void setActiveCameraNum(int num);

    int activeMicrophoneNum() const;
    void setActiveMicrophoneNum(int num);

signals:
    void settingsSaved(const QString &filePath);
    void saveFailed(const QString &filePath, const QString &errorString);

    void activeChanged();
    void widthChanged();
    void heightChanged();
    void fpsChanged();
    void bitrateKbpsChanged();
    void preferredCameraChanged();
    void videoCodecChanged();
    void audioCodecChanged();
    void audioSampleRateChanged();
    void audioBitrateKbpsChanged();
    void audioChannelsChanged();
    void maxBitrateKbpsChanged();
    void outputUrlChanged();
    void preferredMicrophoneIdChanged();
    void activeCameraNumChanged();
    void activeMicrophoneNumChanged();
    void userIntentEpochChanged();

private:
    QString m_settingsFilePath;
    bool    m_active = false;
    quint64 m_userIntentEpoch = 0;

    int     m_width = 1920;
    // Built-in camera default. The mediamtx-side daemon is configured
    // separately at 1920x1080; Wingout's camera daemon path defaults to the
    // Pixel camera's 1920x1920 input.
    int     m_height = 1920;
    int     m_fps = 60;
    int     m_bitrateKbps = 8000;
    QString m_preferredCamera = QStringLiteral("Front");

    QString m_videoCodec;
    QString m_audioCodec = QStringLiteral("aac");
    int     m_audioSampleRate = 48000;
    int     m_audioBitrateKbps = 64;
    int     m_audioChannels = 1;
    int     m_maxBitrateKbps = 12000;
    QString m_outputUrl;

    int     m_preferredMicrophoneId = 0;
    int     m_activeCameraNum = -1;
    int     m_activeMicrophoneNum = -1;

    void initSettingsPath();
    void loadFromFile();
    bool writeToFile();
    QString normalizeVideoCodec(const QString &codec) const;
};
