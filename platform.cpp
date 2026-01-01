

#include "wifi.h"
#include <qglobal.h>
#include <qvariant.h>

#include <QFile>
#include <QRegularExpression>

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
                    const QString &security, const QString &password) {
  return -1;
}
void disconnectRequestedWiFiAP(int requestId) {}
void disconnectAllRequestedWiFiAPs() {}
QList<ChannelQualityInfo> getChannelQualityInfo() { return {}; }
bool isHotspotEnabled() { return false; }
void setHotspotEnabled(bool enabled) {}
bool isLocalHotspotEnabled() { return false; }
void setLocalHotspotEnabled(bool enabled) {}
QString getLocalOnlyHotspotInfoJSON() { return "{}"; }
QString getHotspotConfigurationJSON() { return "{}"; }
void saveHotspotConfiguration(const QString &ssid, const QString &psk) {}
#endif

QWiFiInfo *Platform::getCurrentWiFiConnection() {
  WiFiInfo info = ::getCurrentWiFiConnection();
  m_currentWiFiConnection->setFrom(info);
  return m_currentWiFiConnection;
}

bool Platform::isHotspotEnabled() {
  return ::isHotspotEnabled();
}

void Platform::setHotspotEnabled(bool enabled) {
  ::setHotspotEnabled(enabled);
  if (m_isHotspotEnabled != enabled) {
    m_isHotspotEnabled = enabled;
    emit isHotspotEnabledChanged(enabled);
  }
}

bool Platform::isLocalHotspotEnabled() {
  return ::isLocalHotspotEnabled();
}

void Platform::setLocalHotspotEnabled(bool enabled) {
  ::setLocalHotspotEnabled(enabled);
  if (m_isLocalHotspotEnabled != enabled) {
    m_isLocalHotspotEnabled = enabled;
    emit isLocalHotspotEnabledChanged(enabled);
  }
}

QVariantMap Platform::getLocalOnlyHotspotInfo() {
  QString jsonStr = ::getLocalOnlyHotspotInfoJSON();
  const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
  if (!doc.isObject()) {
    return QVariantMap();
  }
  return doc.object().toVariantMap();
}

QVariantMap Platform::getHotspotConfiguration() {
  QString jsonStr = ::getHotspotConfigurationJSON();
  const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
  if (!doc.isObject()) {
    return QVariantMap();
  }
  return doc.object().toVariantMap();
}

void Platform::saveHotspotConfiguration(const QString &ssid, const QString &psk) {
  ::saveHotspotConfiguration(ssid, psk);
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

QList<QChannelQualityInfo *> Platform::getChannelsQualityInfo() {
  QList<QChannelQualityInfo *> result;
  QList<ChannelQualityInfo> raw = ::getChannelsQualityInfo();
  for (const ChannelQualityInfo &info : raw) {
    QChannelQualityInfo *obj = new QChannelQualityInfo(this);
    obj->setFrom(info);
    result.append(obj);
  }
  return result;
}

QList<ChannelQualityInfo>
parseFileWithChannelsQuality(const QString &filePath) {
  QList<ChannelQualityInfo> list;
  QFile file(filePath);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
    return list;

  const QByteArray raw = file.readAll();
  file.close();
  const QString content = QString::fromUtf8(raw).trimmed();
  if (content.isEmpty())
    return list;

  const QStringList parts =
      content.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
  for (int i = 0; i < parts.size() && i < 3; ++i) {
    bool ok = false;
    const int quality = parts.at(i).toInt(&ok);
    if (!ok)
      continue;

    ChannelQualityInfo info;
    info.name = QStringLiteral("channel%1").arg(i + 1);
    info.quality = quality;
    list.append(info);
  }

  return list;
}