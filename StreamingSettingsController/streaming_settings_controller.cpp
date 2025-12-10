#include "streaming_settings_controller.h"

#include <QStandardPaths>
#include <QDir>
#include <QFile>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDateTime>

StreamingSettingsController::StreamingSettingsController(QObject *parent)
    : QObject(parent)
{
    initSettingsPath();
}

void StreamingSettingsController::initSettingsPath()
{
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);

    if (tempDir.isEmpty())
        tempDir = QDir::tempPath();

    if (tempDir.isEmpty())
        tempDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);

    QDir dir(tempDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    m_settingsFilePath = dir.filePath(QStringLiteral("streaming_settings.json"));
}

QString StreamingSettingsController::settingsFilePath() const
{
    return m_settingsFilePath;
}

bool StreamingSettingsController::saveSettings(int width,
                                               int height,
                                               int fps,
                                               int bitrateKbps,
                                               const QString &preferredCamera)
{
    if (m_settingsFilePath.isEmpty())
        return false;

    QJsonObject root;
    root.insert(QStringLiteral("width"), width);
    root.insert(QStringLiteral("height"), height);
    root.insert(QStringLiteral("fps"), fps);
    root.insert(QStringLiteral("bitrateKbps"), bitrateKbps);
    root.insert(QStringLiteral("preferredCamera"), preferredCamera);
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

    emit settingsSaved(m_settingsFilePath);
    return true;
}