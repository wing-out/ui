#include "streaming_settings_controller.h"

#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QDateTime>

namespace {
constexpr int  DefaultWidth             = 1920;
// Built-in camera mission default. The separate mediamtx-side ffstream consumes
// 1920x1080; Wingout configures only the ffstream-camera daemon, whose Pixel
// 8a camera input is 1920x1920.
constexpr int  DefaultHeight            = 1920;
constexpr int  DefaultFps               = 60;
constexpr int  DefaultBitrateKbps       = 8000;
const char    *DefaultCamera            = "Front";
const char    *MissionVideoCodec        = "av1_mediacodec";
const char    *DefaultAudioCodec        = "aac";
constexpr int  DefaultAudioSampleRate   = 48000;
constexpr int  DefaultAudioBitrateKbps  = 64;
constexpr int  DefaultAudioChannels     = 1;
constexpr int  DefaultMaxBitrateKbps    = 12000;
constexpr int  DefaultPreferredMicId    = 0;

// Persisted-JSON schema version. Bump whenever the on-disk shape of
// streaming_settings.json changes incompatibly (renamed/moved/typed-differently
// fields). loadFromFile() refuses to consume a file whose recorded version
// does not match SettingsSchemaVersion: the call falls back to defaults
// silently rather than partial-load (which previously silently mixed old
// and new field names with no user-visible signal). Files written before
// the version key existed (legacy) are treated as version 1 (the
// .toInt(1) default in loadFromFile); after this 1→2 bump such legacy
// files are rejected, falling back to defaults — the user must re-enter
// outputUrl. add_or_change_field upgrades require bumping the constant
// AND a migration block in loadFromFile().
//
// History:
//  v1 → v2 (#350): writeToFile() no longer persists "active" (now derived
//                  from ffstream input registry by the QML reconciler) and
//                  no longer persists "ffstreamCameraArgs" (the QProcess
//                  supervisor was dropped — wingout now drives the
//                  loop-respawned ffstream-camera daemon via the gRPC
//                  client on port 3594).
constexpr int SettingsSchemaVersion = 2;
const char *SettingsSchemaVersionKey = "settingsSchemaVersion";
} // namespace

StreamingSettingsController::StreamingSettingsController(QObject *parent)
    : QObject(parent)
{
    // Initialize defaults
    m_width             = DefaultWidth;
    m_height            = DefaultHeight;
    m_fps               = DefaultFps;
    m_bitrateKbps       = DefaultBitrateKbps;
    m_preferredCamera   = QString::fromUtf8(DefaultCamera);
    m_videoCodec        = missionVideoCodec();
    m_audioCodec        = QString::fromUtf8(DefaultAudioCodec);
    m_audioSampleRate   = DefaultAudioSampleRate;
    m_audioBitrateKbps  = DefaultAudioBitrateKbps;
    m_audioChannels     = DefaultAudioChannels;
    m_maxBitrateKbps    = DefaultMaxBitrateKbps;
    m_preferredMicrophoneId = DefaultPreferredMicId;
    m_activeCameraNum     = -1;
    m_activeMicrophoneNum = -1;
    m_active            = false;

    initSettingsPath();
    loadFromFile();   // auto-recover, if file already exists
}

void StreamingSettingsController::initSettingsPath()
{
    // Standard temp dir (works on Android as app-specific temp). [DOC]
    // QStandardPaths::TempLocation is a writable location for temporary files.
    // QDir::tempPath() is a generic temp-dir helper. [DOC]
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tempDir.isEmpty())
        tempDir = QDir::tempPath();
    if (tempDir.isEmpty())
        tempDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);

    QDir dir(tempDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    // e.g.: /tmp/streaming_settings.json on Linux; app temp/cache path on Android.
    m_settingsFilePath = dir.filePath(QStringLiteral("streaming_settings.json"));
}

QString StreamingSettingsController::settingsFilePath() const
{
    return m_settingsFilePath;
}

bool StreamingSettingsController::isActive() const
{
    return m_active;
}

int StreamingSettingsController::width() const
{
    return m_width;
}

void StreamingSettingsController::setWidth(int w)
{
    if (m_width == w)
        return;
    m_width = w;
    emit widthChanged();
}

int StreamingSettingsController::height() const
{
    return m_height;
}

void StreamingSettingsController::setHeight(int h)
{
    if (m_height == h)
        return;
    m_height = h;
    emit heightChanged();
}

int StreamingSettingsController::fps() const
{
    return m_fps;
}

void StreamingSettingsController::setFps(int fps)
{
    if (m_fps == fps)
        return;
    m_fps = fps;
    emit fpsChanged();
}

int StreamingSettingsController::bitrateKbps() const
{
    return m_bitrateKbps;
}

void StreamingSettingsController::setBitrateKbps(int bitrate)
{
    if (m_bitrateKbps == bitrate)
        return;
    m_bitrateKbps = bitrate;
    emit bitrateKbpsChanged();
}

QString StreamingSettingsController::preferredCamera() const
{
    return m_preferredCamera;
}

void StreamingSettingsController::setPreferredCamera(const QString &camera)
{
    if (m_preferredCamera == camera)
        return;
    m_preferredCamera = camera;
    emit preferredCameraChanged();
    // Standard setter contract (used by every property setter on this
    // class): persist while active so live UI changes survive process
    // restart. Pre-activation property edits are buffered and committed
    // by activate(); writeToFile() only touches the JSON once settings
    // are active.
    if (m_active)
        writeToFile();
}

QString StreamingSettingsController::videoCodec() const
{
    return m_videoCodec;
}

QString StreamingSettingsController::missionVideoCodec() const
{
    return QString::fromUtf8(MissionVideoCodec);
}

QString StreamingSettingsController::normalizeVideoCodec(const QString &codec) const
{
    Q_UNUSED(codec);
    return missionVideoCodec();
}

void StreamingSettingsController::setVideoCodec(const QString &codec)
{
    const QString normalizedCodec = normalizeVideoCodec(codec);
    if (m_videoCodec == normalizedCodec)
        return;
    m_videoCodec = normalizedCodec;
    emit videoCodecChanged();
    // Persist while active so live UI changes survive process restart.
    // See setPreferredCamera for the contract — every setter must
    // behave identically when m_active is true.
    if (m_active)
        writeToFile();
}

QString StreamingSettingsController::audioCodec() const
{
    return m_audioCodec;
}

void StreamingSettingsController::setAudioCodec(const QString &codec)
{
    if (m_audioCodec == codec)
        return;
    m_audioCodec = codec;
    emit audioCodecChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::audioSampleRate() const
{
    return m_audioSampleRate;
}

void StreamingSettingsController::setAudioSampleRate(int rate)
{
    if (m_audioSampleRate == rate)
        return;
    m_audioSampleRate = rate;
    emit audioSampleRateChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::audioBitrateKbps() const
{
    return m_audioBitrateKbps;
}

void StreamingSettingsController::setAudioBitrateKbps(int kbps)
{
    if (m_audioBitrateKbps == kbps)
        return;
    m_audioBitrateKbps = kbps;
    emit audioBitrateKbpsChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::audioChannels() const
{
    return m_audioChannels;
}

void StreamingSettingsController::setAudioChannels(int channels)
{
    if (m_audioChannels == channels)
        return;
    m_audioChannels = channels;
    emit audioChannelsChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::maxBitrateKbps() const
{
    return m_maxBitrateKbps;
}

void StreamingSettingsController::setMaxBitrateKbps(int kbps)
{
    if (m_maxBitrateKbps == kbps)
        return;
    m_maxBitrateKbps = kbps;
    emit maxBitrateKbpsChanged();
    if (m_active)
        writeToFile();
}

QString StreamingSettingsController::outputUrl() const
{
    return m_outputUrl;
}

void StreamingSettingsController::setOutputUrl(const QString &url)
{
    if (m_outputUrl == url)
        return;
    m_outputUrl = url;
    emit outputUrlChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::preferredMicrophoneId() const
{
    return m_preferredMicrophoneId;
}

void StreamingSettingsController::setPreferredMicrophoneId(int id)
{
    if (m_preferredMicrophoneId == id)
        return;
    m_preferredMicrophoneId = id;
    emit preferredMicrophoneIdChanged();
    if (m_active)
        writeToFile();
}

int StreamingSettingsController::activeCameraNum() const
{
    return m_activeCameraNum;
}

void StreamingSettingsController::setActiveCameraNum(int num)
{
    if (m_activeCameraNum == num)
        return;
    m_activeCameraNum = num;
    emit activeCameraNumChanged();
}

int StreamingSettingsController::activeMicrophoneNum() const
{
    return m_activeMicrophoneNum;
}

void StreamingSettingsController::setActiveMicrophoneNum(int num)
{
    if (m_activeMicrophoneNum == num)
        return;
    m_activeMicrophoneNum = num;
    emit activeMicrophoneNumChanged();
}

bool StreamingSettingsController::saveSettings(int width,
                                               int height,
                                               int fps,
                                               int bitrateKbps,
                                               const QString &preferredCamera)
{
    setWidth(width);
    setHeight(height);
    setFps(fps);
    setBitrateKbps(bitrateKbps);
    setPreferredCamera(preferredCamera);

    if (!writeToFile())
        return false;

    if (!m_active) {
        m_active = true;
        emit activeChanged();
    }

    emit settingsSaved(m_settingsFilePath);
    return true;
}

bool StreamingSettingsController::activate()
{
    // Bump user-intent epoch BEFORE writing/emitting so any reconcile RPC
    // dispatched concurrently sees the new epoch and discards its stale reply.
    ++m_userIntentEpoch;
    emit userIntentEpochChanged();

    // Use current properties
    if (!writeToFile())
        return false;

    if (!m_active) {
        m_active = true;
        emit activeChanged();
    }

    emit settingsSaved(m_settingsFilePath);
    return true;
}

void StreamingSettingsController::setActiveFromReconciliation(bool actuallyActive, quint64 capturedEpoch)
{
    // Stale-reply guard: if the user tapped Activate/Deactivate after the
    // caller sampled userIntentEpoch and dispatched the RPC, drop the result.
    // Otherwise a stale "no inputs yet" reply lands AFTER the user's tap and
    // briefly flips the Active button back, which looks like a UI bug.
    if (capturedEpoch != m_userIntentEpoch) return;
    if (m_active == actuallyActive) return;
    m_active = actuallyActive;
    emit activeChanged();
    // No writeToFile(): JSON's active field is no longer authoritative
    // (see loadFromFile). Persisted file just records last-applied
    // settings; m_active is rederived from ffstream every boot.
}

quint64 StreamingSettingsController::userIntentEpoch() const
{
    return m_userIntentEpoch;
}

void StreamingSettingsController::bumpUserIntentEpoch()
{
    ++m_userIntentEpoch;
    emit userIntentEpochChanged();
}

bool StreamingSettingsController::deactivate()
{
    // Same epoch contract as activate(): bump first so any concurrent
    // reconcile reply is invalidated.
    ++m_userIntentEpoch;
    emit userIntentEpochChanged();

    if (m_settingsFilePath.isEmpty()) {
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        return true;
    }

    QFile file(m_settingsFilePath);
    if (file.exists()) {
        if (!file.remove()) {
            emit saveFailed(m_settingsFilePath, file.errorString());
            return false;
        }
    }

    if (m_active) {
        m_active = false;
        emit activeChanged();
    }

    // We keep the last values in memory; only the persisted file is gone.
    return true;
}

bool StreamingSettingsController::writeToFile()
{
    if (m_settingsFilePath.isEmpty())
        return false;

    QJsonObject root;
    root.insert(QStringLiteral("width"), m_width);
    root.insert(QStringLiteral("height"), m_height);
    root.insert(QStringLiteral("fps"), m_fps);
    root.insert(QStringLiteral("bitrateKbps"), m_bitrateKbps);
    root.insert(QStringLiteral("preferredCamera"), m_preferredCamera);
    root.insert(QStringLiteral("videoCodec"), normalizeVideoCodec(m_videoCodec));
    root.insert(QStringLiteral("audioCodec"), m_audioCodec);
    root.insert(QStringLiteral("audioSampleRate"), m_audioSampleRate);
    root.insert(QStringLiteral("audioBitrateKbps"), m_audioBitrateKbps);
    root.insert(QStringLiteral("audioChannels"), m_audioChannels);
    root.insert(QStringLiteral("maxBitrateKbps"), m_maxBitrateKbps);
    root.insert(QStringLiteral("outputUrl"), m_outputUrl);
    root.insert(QStringLiteral("preferredMicrophoneId"), m_preferredMicrophoneId);
    // Schema version is written on every save so a future loader can detect
    // an incompatible on-disk shape and reset to defaults instead of
    // partial-loading. See SettingsSchemaVersion definition for the bump
    // contract.
    root.insert(QString::fromUtf8(SettingsSchemaVersionKey), SettingsSchemaVersion);
    // NOTE: the "active" key was deliberately removed. m_active is no longer
    // derived from the JSON file (see loadFromFile()) — the QML reconciler
    // re-derives it from ffstream's input registry on every boot. Writing
    // the field would be dead data and re-introduces the temptation to
    // trust a stale persisted value.
    root.insert(QStringLiteral("timestampUtc"),
                QDateTime::currentDateTimeUtc().toString(Qt::ISODate));

    const QJsonDocument doc(root);
    const QByteArray jsonData = doc.toJson(QJsonDocument::Indented);

    QFile file(m_settingsFilePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        emit saveFailed(m_settingsFilePath, file.errorString());
        return false;
    }

    const qint64 bytesWritten = file.write(jsonData);
    file.close();

    if (bytesWritten != jsonData.size()) {
        emit saveFailed(m_settingsFilePath, QStringLiteral("Short write"));
        return false;
    }

    return true;
}

void StreamingSettingsController::loadFromFile()
{
    if (m_settingsFilePath.isEmpty())
        return;

    QFile file(m_settingsFilePath);
    if (!file.exists()) {
        // File does not exist: keep defaults, mark inactive
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        return;
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        emit saveFailed(m_settingsFilePath, file.errorString());
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        return;
    }

    const QByteArray data = file.readAll();
    file.close();

    QJsonParseError parseError;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    if (parseError.error != QJsonParseError::NoError || !doc.isObject()) {
        emit saveFailed(m_settingsFilePath,
                        QStringLiteral("Invalid JSON: %1").arg(parseError.errorString()));
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        return;
    }

    const QJsonObject obj = doc.object();

    // Schema gate: refuse to consume a file whose recorded version does
    // not match SettingsSchemaVersion. Pre-version files (legacy, written
    // before this key existed) default to version 1 via .toInt(1). After
    // the v1→v2 bump (#350) such legacy files no longer match the current
    // version: they fall through to defaults here, leaving m_active=false
    // and prompting the user to re-enter outputUrl + tap Activate. This
    // is intentional — the v1→v2 transition removed two fields ("active"
    // and "ffstreamCameraArgs") whose semantics are no longer trustworthy,
    // and silently consuming a v1 file would re-introduce stale state.
    const int onDiskVersion =
        obj.value(QString::fromUtf8(SettingsSchemaVersionKey)).toInt(1);
    if (onDiskVersion != SettingsSchemaVersion) {
        emit saveFailed(m_settingsFilePath,
                        QStringLiteral("Schema version mismatch: file=%1 expected=%2 — using defaults")
                            .arg(onDiskVersion).arg(SettingsSchemaVersion));
        if (m_active) {
            m_active = false;
            emit activeChanged();
        }
        return;
    }

    const QString persistedVideoCodec =
        obj.value(QStringLiteral("videoCodec")).toString(missionVideoCodec());
    // showAllCodecs is a tombstoned v2 key: older current-schema files may
    // contain it, but it no longer has a live UI/API surface.
    const bool needsCanonicalRewrite =
        persistedVideoCodec != normalizeVideoCodec(persistedVideoCodec)
        || obj.contains(QStringLiteral("showAllCodecs"));

    setWidth(obj.value(QStringLiteral("width")).toInt(DefaultWidth));
    setHeight(obj.value(QStringLiteral("height")).toInt(DefaultHeight));
    setFps(obj.value(QStringLiteral("fps")).toInt(DefaultFps));
    setBitrateKbps(obj.value(QStringLiteral("bitrateKbps")).toInt(DefaultBitrateKbps));
    setPreferredCamera(obj.value(QStringLiteral("preferredCamera"))
                           .toString(QString::fromUtf8(DefaultCamera)));
    setVideoCodec(persistedVideoCodec);
    setAudioCodec(obj.value(QStringLiteral("audioCodec"))
                      .toString(QString::fromUtf8(DefaultAudioCodec)));
    setAudioSampleRate(obj.value(QStringLiteral("audioSampleRate"))
                           .toInt(DefaultAudioSampleRate));
    setAudioBitrateKbps(obj.value(QStringLiteral("audioBitrateKbps"))
                            .toInt(DefaultAudioBitrateKbps));
    setAudioChannels(obj.value(QStringLiteral("audioChannels"))
                         .toInt(DefaultAudioChannels));
    setMaxBitrateKbps(obj.value(QStringLiteral("maxBitrateKbps"))
                          .toInt(DefaultMaxBitrateKbps));
    setOutputUrl(obj.value(QStringLiteral("outputUrl")).toString(QString()));
    setPreferredMicrophoneId(obj.value(QStringLiteral("preferredMicrophoneId"))
                                 .toInt(DefaultPreferredMicId));

    if (needsCanonicalRewrite)
        writeToFile();

    // Do NOT trust the persisted "active" flag. Active state is owned by
    // ffstream's input registry — the JSON file proves only that the user
    // once tapped Activate, not that the inputs are still registered. Boot
    // defaults m_active=false (see ctor); the QML reconciler in Main.qml's
    // onChannelChanged calls setActiveFromReconciliation() once it has
    // confirmed priority-0 inputs are registered.
    //
    // Emit if we are clobbering a previously-true value: today loadFromFile
    // is only invoked from the constructor (where m_active starts false), but
    // a future "reload from disk" caller would silently desync UI bindings
    // without this guard. Cheap insurance.
    if (m_active) {
        m_active = false;
        emit activeChanged();
    }
}
