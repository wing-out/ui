#ifndef MOCK_PLATFORM_H
#define MOCK_PLATFORM_H

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

class MockPlatform : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float cpuUtilization READ cpuUtilization NOTIFY cpuUtilizationChanged)
    Q_PROPERTY(float memoryUtilization READ memoryUtilization NOTIFY memoryUtilizationChanged)
    Q_PROPERTY(QVariantList temperatures READ temperatures NOTIFY temperaturesChanged)
    Q_PROPERTY(int signalStrength READ signalStrength NOTIFY signalStrengthChanged)
    Q_PROPERTY(bool isHotspotEnabled READ isHotspotEnabled NOTIFY isHotspotEnabledChanged)

public:
    explicit MockPlatform(QObject *parent = nullptr) : QObject(parent) {}

    float cpuUtilization() const { return m_cpu; }
    float memoryUtilization() const { return m_memory; }
    QVariantList temperatures() const { return m_temps; }
    int signalStrength() const { return m_signal; }
    bool isHotspotEnabled() const { return m_hotspot; }

    // Test helpers
    Q_INVOKABLE void setTestCpuUtilization(float v) { m_cpu = v; emit cpuUtilizationChanged(); }
    Q_INVOKABLE void setTestMemoryUtilization(float v) { m_memory = v; emit memoryUtilizationChanged(); }
    Q_INVOKABLE void setTestTemperatures(QVariantList t) { m_temps = t; emit temperaturesChanged(); }
    Q_INVOKABLE void setTestSignalStrength(int s) { m_signal = s; emit signalStrengthChanged(); }

    Q_INVOKABLE void updateResources() {}
    Q_INVOKABLE QVariantMap getCurrentWiFiConnection() {
        QVariantMap r;
        r[QStringLiteral("ssid")] = m_wifiSSID;
        r[QStringLiteral("bssid")] = m_wifiBSSID;
        r[QStringLiteral("rssi")] = m_wifiRSSI;
        return r;
    }
    Q_INVOKABLE QVariantMap getSafeAreaInsets() {
        QVariantMap r;
        r[QStringLiteral("top")] = 0; r[QStringLiteral("bottom")] = 0;
        r[QStringLiteral("left")] = 0; r[QStringLiteral("right")] = 0;
        return r;
    }
    Q_INVOKABLE void vibrate(quint64, bool) {}
    Q_INVOKABLE void setEnableRunningInBackground(bool) {}

    // Test helpers for WiFi
    Q_INVOKABLE void setTestWiFi(const QString &ssid, const QString &bssid, int rssi) {
        m_wifiSSID = ssid; m_wifiBSSID = bssid; m_wifiRSSI = rssi;
    }

signals:
    void cpuUtilizationChanged();
    void memoryUtilizationChanged();
    void temperaturesChanged();
    void signalStrengthChanged();
    void isHotspotEnabledChanged();

private:
    float m_cpu = 0.35f;
    float m_memory = 0.52f;
    QVariantList m_temps;
    int m_signal = -70;
    bool m_hotspot = false;
    QString m_wifiSSID = QStringLiteral("TestNetwork");
    QString m_wifiBSSID = QStringLiteral("AA:BB:CC:DD:EE:FF");
    int m_wifiRSSI = -65;
};

#endif // MOCK_PLATFORM_H
