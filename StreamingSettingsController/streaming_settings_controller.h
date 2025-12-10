#pragma once

#include <QObject>
#include <QString>

#include <QtQml/qqmlregistration.h>  // QML_ELEMENT

class StreamingSettingsController : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Expose the path to QML, so you can debug/log where it writes.
    Q_PROPERTY(QString settingsFilePath READ settingsFilePath CONSTANT)

public:
    explicit StreamingSettingsController(QObject *parent = nullptr);

    // Call from QML when "Activate" is pressed
    Q_INVOKABLE bool saveSettings(int width,
                                  int height,
                                  int fps,
                                  int bitrateKbps,
                                  const QString &preferredCamera);

    QString settingsFilePath() const;

signals:
    void settingsSaved(const QString &filePath);
    void saveFailed(const QString &filePath, const QString &errorString);

private:
    QString m_settingsFilePath;
    void initSettingsPath();
};