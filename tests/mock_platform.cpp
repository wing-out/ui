#include "mock_platform.h"

MockPlatform::MockPlatform(QObject *parent) : QObject(parent) {
  // Default temperatures
  QVariantMap cpu;
  cpu["temp"] = 42.5f;
  cpu["type"] = "cpu";
  QVariantMap battery;
  battery["temp"] = 38.0f;
  battery["type"] = "battery";
  m_temperatures = {cpu, battery};

  // WiFi info helper – a plain QObject with dynamic properties
  m_wifiInfoObj = new QObject(this);
  m_wifiInfoObj->setProperty("ssid", m_wifiSSID);
  m_wifiInfoObj->setProperty("bssid", m_wifiBSSID);
  m_wifiInfoObj->setProperty("rssi", m_wifiRSSI);
}

void MockPlatform::setSignalStrength(int strength) {
  if (m_signalStrength != strength) {
    m_signalStrength = strength;
    emit signalStrengthChanged(strength);
  }
}

void MockPlatform::setHotspotEnabled(bool enabled) {
  if (m_isHotspotEnabled != enabled) {
    m_isHotspotEnabled = enabled;
    emit isHotspotEnabledChanged(enabled);
  }
}

void MockPlatform::setLocalHotspotEnabled(bool enabled) {
  if (m_isLocalHotspotEnabled != enabled) {
    m_isLocalHotspotEnabled = enabled;
    emit isLocalHotspotEnabledChanged(enabled);
  }
}

QObject *MockPlatform::getCurrentWiFiConnection() { return m_wifiInfoObj; }

QVariantMap MockPlatform::getLocalOnlyHotspotInfo() {
  return {{"ssid", "TestHotspot"}, {"password", "testpass123"}};
}

QVariantMap MockPlatform::getHotspotConfiguration() {
  return {{"ssid", "WingOutAP"}, {"psk", "wingout123"}};
}

QVariantList MockPlatform::getChannelsQualityInfo() {
  QVariantList channels;
  for (int i = 1; i <= 3; ++i) {
    QObject *ch = new QObject(this);
    ch->setProperty("name", QString("channel%1").arg(i));
    ch->setProperty("quality", 80 + i * 5);
    channels.append(QVariant::fromValue(ch));
  }
  return channels;
}

QVariantMap MockPlatform::getSafeAreaInsets() {
  return {{"top", 0}, {"bottom", 0}, {"left", 0}, {"right", 0}};
}

// --- Test helpers ---

void MockPlatform::setTestCpuUtilization(float v) {
  m_cpuUtilization = v;
  emit cpuUtilizationChanged();
}

void MockPlatform::setTestMemoryUtilization(float v) {
  m_memoryUtilization = v;
  emit memoryUtilizationChanged();
}

void MockPlatform::setTestTemperatures(const QVariantList &t) {
  m_temperatures = t;
  emit temperaturesChanged();
}

void MockPlatform::setTestWiFi(const QString &ssid, const QString &bssid,
                                int rssi) {
  m_wifiSSID = ssid;
  m_wifiBSSID = bssid;
  m_wifiRSSI = rssi;
  m_wifiInfoObj->setProperty("ssid", ssid);
  m_wifiInfoObj->setProperty("bssid", bssid);
  m_wifiInfoObj->setProperty("rssi", rssi);
}
