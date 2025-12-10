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

    // Settings themselves, fully readable/writable from QML
    Q_PROPERTY(int width READ width WRITE setWidth NOTIFY widthChanged)
    Q_PROPERTY(int height READ height WRITE setHeight NOTIFY heightChanged)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)
    Q_PROPERTY(int bitrateKbps READ bitrateKbps WRITE setBitrateKbps NOTIFY bitrateKbpsChanged)
    Q_PROPERTY(QString preferredCamera READ preferredCamera WRITE setPreferredCamera NOTIFY preferredCameraChanged)

public:
    explicit StreamingSettingsController(QObject *parent = nullptr);

    // Activate: write current properties to file and mark active=true
    Q_INVOKABLE bool activate();

    // Deactivate: delete the file (if present) and mark active=false
    Q_INVOKABLE bool deactivate();

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

signals:
    void settingsSaved(const QString &filePath);
    void saveFailed(const QString &filePath, const QString &errorString);

    void activeChanged();
    void widthChanged();
    void heightChanged();
    void fpsChanged();
    void bitrateKbpsChanged();
    void preferredCameraChanged();

private:
    QString m_settingsFilePath;
    bool    m_active = false;

    int     m_width = 1920;
    int     m_height = 1080;
    int     m_fps = 60;
    int     m_bitrateKbps = 8000;
    QString m_preferredCamera = QStringLiteral("Front");

    void initSettingsPath();
    void loadFromFile();
    bool writeToFile();
};