#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlengine.h>

/// MockPlatform provides a headless stub of the Platform class so that QML
/// components can be tested without real hardware (WiFi, BLE, sensors, etc.).
/// All methods return controllable test data.
class MockPlatform : public QObject {
  Q_OBJECT
  Q_PROPERTY(int signalStrength READ getSignalStrength WRITE setSignalStrength
                 NOTIFY signalStrengthChanged)
  Q_PROPERTY(bool isHotspotEnabled READ isHotspotEnabled WRITE setHotspotEnabled
                 NOTIFY isHotspotEnabledChanged)
  Q_PROPERTY(bool isLocalHotspotEnabled READ isLocalHotspotEnabled
                 WRITE setLocalHotspotEnabled
                     NOTIFY isLocalHotspotEnabledChanged)
  Q_PROPERTY(QString hotspotIPAddress READ getHotspotIPAddress
                 NOTIFY hotspotIPAddressChanged)
  Q_PROPERTY(
      float cpuUtilization READ getCpuUtilization NOTIFY cpuUtilizationChanged)
  Q_PROPERTY(float memoryUtilization READ getMemoryUtilization
                 NOTIFY memoryUtilizationChanged)
  Q_PROPERTY(
      QVariantList temperatures READ getTemperatures NOTIFY temperaturesChanged)

public:
  explicit MockPlatform(QObject *parent = nullptr);

  // Power management
  Q_INVOKABLE void setEnableRunningInBackground(bool) {}

  // Resources
  Q_INVOKABLE float getCpuUtilization() { return m_cpuUtilization; }
  Q_INVOKABLE float getMemoryUtilization() { return m_memoryUtilization; }
  Q_INVOKABLE QVariantList getTemperatures() { return m_temperatures; }
  Q_INVOKABLE void updateResources() {} // no-op in test

  // Vibrate
  Q_INVOKABLE void vibrate(quint64, bool) {}

  // Mobile signal
  Q_INVOKABLE void startMonitoringSignalStrength() {}
  Q_INVOKABLE int getSignalStrength() { return m_signalStrength; }
  void setSignalStrength(int strength);

  // WiFi
  Q_INVOKABLE QObject *getCurrentWiFiConnection();
  Q_INVOKABLE bool isHotspotEnabled() { return m_isHotspotEnabled; }
  Q_INVOKABLE void setHotspotEnabled(bool enabled);
  Q_INVOKABLE bool isLocalHotspotEnabled() { return m_isLocalHotspotEnabled; }
  Q_INVOKABLE void setLocalHotspotEnabled(bool enabled);
  Q_INVOKABLE QString getHotspotIPAddress() { return m_hotspotIPAddress; }
  Q_INVOKABLE QVariantMap getLocalOnlyHotspotInfo();
  Q_INVOKABLE QVariantMap getHotspotConfiguration();
  Q_INVOKABLE void saveHotspotConfiguration(const QString &, const QString &) {}
  Q_INVOKABLE void startWiFiScan() {}
  Q_INVOKABLE QVariantList getWiFiScanResults() { return {}; }
  Q_INVOKABLE int connectToWiFiAP(const QString &, const QString &,
                                   const QString &, const QString &) {
    return 0;
  }
  Q_INVOKABLE void disconnectRequestedWiFiAP(int) {}
  Q_INVOKABLE void disconnectAllRequestedWiFiAPs() {}
  Q_INVOKABLE void refreshWiFiState() {}

  // Network
  Q_INVOKABLE QVariantList getChannelsQualityInfo();

  // UI
  Q_INVOKABLE QVariantMap getSafeAreaInsets();

  // --- Test helpers (not called by QML, used by tests to set state) ---
  void setTestCpuUtilization(float v);
  void setTestMemoryUtilization(float v);
  void setTestTemperatures(const QVariantList &t);
  void setTestWiFi(const QString &ssid, const QString &bssid, int rssi);

signals:
  void signalStrengthChanged(int strength);
  void isHotspotEnabledChanged(bool enabled);
  void isLocalHotspotEnabledChanged(bool enabled);
  void hotspotIPAddressChanged();
  void cpuUtilizationChanged();
  void memoryUtilizationChanged();
  void temperaturesChanged();

private:
  int m_signalStrength = 75;
  bool m_isHotspotEnabled = false;
  bool m_isLocalHotspotEnabled = false;
  QString m_hotspotIPAddress = "192.168.49.1";
  float m_cpuUtilization = 35.0f;
  float m_memoryUtilization = 52.0f;
  QVariantList m_temperatures;

  // WiFi mock data
  QString m_wifiSSID = "TestNetwork";
  QString m_wifiBSSID = "AA:BB:CC:DD:EE:FF";
  int m_wifiRSSI = -55;

  // Owned helper object returned by getCurrentWiFiConnection()
  QObject *m_wifiInfoObj = nullptr;
};
