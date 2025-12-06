
#include "wifi.h"
#include <qglobal.h>
#include <qvariant.h>

#ifdef Q_OS_ANDROID
#define _PLATFORM_IS_SET
#include "platform_android.cpp"
#endif

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
#define _PLATFORM_IS_SET
#include "platform_linux.cpp"
#endif

#ifdef _PLATFORM_IS_SET
#undef _PLATFORM_IS_SET
#else
#include "platform.h"
void Platform::vibrate(uint64_t duration_ms, bool is_notification) {}
void Platform::setEnableRunningInBackground(bool value) {}
void Platform::startMonitoringSignalStrength() {}
WiFiInfo getCurrentWiFiConnection() {}
void startWiFiScan() {}
QVector<WiFiInfo> getWiFiScanResults() {}
int connectToWiFiAP(const QString &ssid, const QString &bssid,
                              const QString &security,
                              const QString &password) {
  return -1;
}
void disconnectRequestedWiFiAP(int requestId) {}
void disconnectAllRequestedWiFiAPs() {}
#endif

QWiFiInfo *Platform::getCurrentWiFiConnection() {
  WiFiInfo info = ::getCurrentWiFiConnection();
  m_currentWiFiConnection->setFrom(info);
  return m_currentWiFiConnection;
}

QVector<QWiFiInfo *> Platform::getWiFiScanResults() {
  // Drop old objects
  qDeleteAll(m_scanResults);
  m_scanResults.clear();

  const QVector<WiFiInfo> raw = ::getWiFiScanResults();

  m_scanResults.reserve(raw.size());
  for (const WiFiInfo &r : raw) {
    auto *obj = new QWiFiInfo(this);
    obj->setFrom(r);
    m_scanResults.append(obj);
  }

  return m_scanResults;
}

void Platform::startWiFiScan() { ::startWiFiScan(); }

int Platform::connectToWiFiAP(const QString &ssid, const QString &bssid,
                              const QString &security,
                              const QString &password) {
  return ::connectToWiFiAP(ssid, bssid, security, password);
}

void Platform::disconnectRequestedWiFiAP(int requestId) {
  ::disconnectRequestedWiFiAP(requestId);
}

void Platform::disconnectAllRequestedWiFiAPs() {
  ::disconnectAllRequestedWiFiAPs();
}
