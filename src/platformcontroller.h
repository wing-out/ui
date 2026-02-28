#ifndef PLATFORMCONTROLLER_H
#define PLATFORMCONTROLLER_H

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

class PlatformController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(float cpuUtilization READ cpuUtilization NOTIFY cpuUtilizationChanged)
    Q_PROPERTY(float memoryUtilization READ memoryUtilization NOTIFY memoryUtilizationChanged)
    Q_PROPERTY(QVariantList temperatures READ temperatures NOTIFY temperaturesChanged)
    Q_PROPERTY(int signalStrength READ signalStrength NOTIFY signalStrengthChanged)
    Q_PROPERTY(bool isHotspotEnabled READ isHotspotEnabled NOTIFY isHotspotEnabledChanged)

public:
    explicit PlatformController(QObject *parent = nullptr);
    ~PlatformController() override;

    float cpuUtilization() const;
    float memoryUtilization() const;
    QVariantList temperatures() const;
    int signalStrength() const;
    bool isHotspotEnabled() const;

    Q_INVOKABLE void updateResources();
    Q_INVOKABLE QVariantMap getCurrentWiFiConnection();
    Q_INVOKABLE QVariantMap getSafeAreaInsets();
    Q_INVOKABLE void vibrate(quint64 durationMs, bool isNotification);
    Q_INVOKABLE void setEnableRunningInBackground(bool enable);

    // WiFi scanning and connection
    Q_INVOKABLE void startWiFiScan();
    Q_INVOKABLE QVariantList getWiFiScanResults();
    Q_INVOKABLE void connectToWiFiAP(const QString &ssid, const QString &password);
    Q_INVOKABLE void disconnectWiFiAP();
    Q_INVOKABLE void refreshWiFiState();
    Q_INVOKABLE QVariantList getChannelsQualityInfo();
    Q_INVOKABLE void startMonitoringSignalStrength();

    // Hotspot management
    Q_INVOKABLE void setHotspotEnabled(bool enabled);
    Q_INVOKABLE void setLocalHotspotEnabled(bool enabled);
    Q_INVOKABLE bool isLocalHotspotEnabled() const;
    Q_INVOKABLE QString getHotspotIPAddress();
    Q_INVOKABLE QVariantMap getLocalOnlyHotspotInfo();
    Q_INVOKABLE QVariantMap getHotspotConfiguration();
    Q_INVOKABLE void saveHotspotConfiguration(const QString &ssid, const QString &password);

signals:
    void cpuUtilizationChanged();
    void memoryUtilizationChanged();
    void temperaturesChanged();
    void signalStrengthChanged();
    void isHotspotEnabledChanged();
    void wifiScanCompleted();

private:
    float m_cpuUtilization = 0.0f;
    float m_memoryUtilization = 0.0f;
    QVariantList m_temperatures;
    int m_signalStrength = 0;
    bool m_isHotspotEnabled = false;

    quint64 m_prevCpuTotal = 0;
    quint64 m_prevCpuBusy = 0;

    bool m_isLocalHotspotEnabled = false;
    QTimer *m_signalMonitorTimer = nullptr;
};

#endif // PLATFORMCONTROLLER_H
