#include "streaming_settings_controller.h"

#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QDateTime>

namespace {
constexpr int  DefaultWidth        = 1920;
constexpr int  DefaultHeight       = 1080;
constexpr int  DefaultFps          = 60;
constexpr int  DefaultBitrateKbps  = 8000;
const char    *DefaultCamera       = "Front";
} // namespace

StreamingSettingsController::StreamingSettingsController(QObject *parent)
    : QObject(parent)
{
    // Initialize defaults
    m_width          = DefaultWidth;
    m_height         = DefaultHeight;
    m_fps            = DefaultFps;
    m_bitrateKbps    = DefaultBitrateKbps;
    m_preferredCamera = QString::fromUtf8(DefaultCamera);
    m_active         = false;

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

bool StreamingSettingsController::deactivate()
{
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
    root.insert(QStringLiteral("active"), true);
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

    setWidth(obj.value(QStringLiteral("width")).toInt(DefaultWidth));
    setHeight(obj.value(QStringLiteral("height")).toInt(DefaultHeight));
    setFps(obj.value(QStringLiteral("fps")).toInt(DefaultFps));
    setBitrateKbps(obj.value(QStringLiteral("bitrateKbps")).toInt(DefaultBitrateKbps));
    setPreferredCamera(obj.value(QStringLiteral("preferredCamera"))
                           .toString(QString::fromUtf8(DefaultCamera)));

    bool newActive = obj.value(QStringLiteral("active")).toBool(true);
    if (newActive != m_active) {
        m_active = newActive;
        emit activeChanged();
    }
}