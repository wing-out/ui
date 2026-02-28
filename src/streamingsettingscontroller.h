#ifndef STREAMINGSETTINGSCONTROLLER_H
#define STREAMINGSETTINGSCONTROLLER_H

#include <QObject>
#include <QQmlEngine>
#include <QString>

class StreamingSettingsController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool active READ isActive NOTIFY activeChanged)
    Q_PROPERTY(int width READ width WRITE setWidth NOTIFY widthChanged)
    Q_PROPERTY(int height READ height WRITE setHeight NOTIFY heightChanged)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)
    Q_PROPERTY(int bitrateKbps READ bitrateKbps WRITE setBitrateKbps NOTIFY bitrateKbpsChanged)
    Q_PROPERTY(QString preferredCamera READ preferredCamera WRITE setPreferredCamera NOTIFY preferredCameraChanged)

public:
    explicit StreamingSettingsController(QObject *parent = nullptr);
    ~StreamingSettingsController() override;

    bool isActive() const;
    int width() const;
    int height() const;
    int fps() const;
    int bitrateKbps() const;
    QString preferredCamera() const;

    void setWidth(int w);
    void setHeight(int h);
    void setFps(int f);
    void setBitrateKbps(int br);
    void setPreferredCamera(const QString &cam);

    Q_INVOKABLE void activate();
    Q_INVOKABLE void deactivate();
    Q_INVOKABLE void saveSettings();
    Q_INVOKABLE void loadSettings();

signals:
    void activeChanged();
    void widthChanged();
    void heightChanged();
    void fpsChanged();
    void bitrateKbpsChanged();
    void preferredCameraChanged();

private:
    bool m_active = false;
    int m_width = 1920;
    int m_height = 1080;
    int m_fps = 30;
    int m_bitrateKbps = 6000;
    QString m_preferredCamera;
};

#endif // STREAMINGSETTINGSCONTROLLER_H
