

#include "wifi.h"
#include <qglobal.h>
#include <qvariant.h>

#include <QFile>
#include <QDir>
#include <QTextStream>
#include <QRegularExpression>
#include <QJsonDocument>
#include <QJsonObject>

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
QString getHotspotIPAddress() { return ""; }
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
  return m_isHotspotEnabled;
}

void Platform::setHotspotEnabled(bool enabled) {
  ::setHotspotEnabled(enabled);
  if (m_isHotspotEnabled != enabled) {
    m_isHotspotEnabled = enabled;
    emit isHotspotEnabledChanged(enabled);
  }
}

bool Platform::isLocalHotspotEnabled() {
  return m_isLocalHotspotEnabled;
}

void Platform::setLocalHotspotEnabled(bool enabled) {
  ::setLocalHotspotEnabled(enabled);
  if (m_isLocalHotspotEnabled != enabled) {
    m_isLocalHotspotEnabled = enabled;
    emit isLocalHotspotEnabledChanged(enabled);
  }
}

QString Platform::getHotspotIPAddress() {
  return ::getHotspotIPAddress();
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

void Platform::updateResources() {
  // CPU
  {
    QFile file("/proc/stat");
    if (file.open(QIODevice::ReadOnly)) {
      QTextStream stream(&file);
      QString line = stream.readLine();
      if (line.startsWith("cpu ")) {
        QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
        if (parts.size() >= 5) {
          uint64_t user = parts[1].toULongLong();
          uint64_t nice = parts[2].toULongLong();
          uint64_t system = parts[3].toULongLong();
          uint64_t idle = parts[4].toULongLong();
          uint64_t iowait = parts.size() > 5 ? parts[5].toULongLong() : 0;
          uint64_t irq = parts.size() > 6 ? parts[6].toULongLong() : 0;
          uint64_t softirq = parts.size() > 7 ? parts[7].toULongLong() : 0;
          uint64_t steal = parts.size() > 8 ? parts[8].toULongLong() : 0;

          uint64_t total = user + nice + system + idle + iowait + irq + softirq + steal;
          uint64_t idleCombined = idle + iowait;

          if (m_lastCpuTotal != 0) {
            uint64_t diffTotal = total - m_lastCpuTotal;
            uint64_t diffIdle = idleCombined - m_lastCpuIdle;
            if (diffTotal > 0) {
              m_cpuUtilization = static_cast<float>(diffTotal - diffIdle) / diffTotal;
              emit cpuUtilizationChanged();
            }
          }
          m_lastCpuTotal = total;
          m_lastCpuIdle = idleCombined;
        }
      }
    }
  }

  // Memory
  {
    QFile file("/proc/meminfo");
    if (file.open(QIODevice::ReadOnly)) {
      QTextStream stream(&file);
      uint64_t totalMem = 0;
      uint64_t availMem = 0;
      uint64_t freeMem = 0;
      uint64_t buffers = 0;
      uint64_t cached = 0;
      uint64_t sReclaimable = 0;
      bool hasAvail = false;

      QString line;
      while (stream.readLineInto(&line)) {
        QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
        if (parts.size() < 2)
          continue;
        uint64_t value = parts[1].toULongLong();

        if (line.startsWith("MemTotal:")) {
          totalMem = value;
        } else if (line.startsWith("MemAvailable:")) {
          availMem = value;
          hasAvail = true;
        } else if (line.startsWith("MemFree:")) {
          freeMem = value;
        } else if (line.startsWith("Buffers:")) {
          buffers = value;
        } else if (line.startsWith("Cached:")) {
          cached = value;
        } else if (line.startsWith("SReclaimable:")) {
          sReclaimable = value;
        }
      }
      if (!hasAvail) {
        availMem = freeMem + buffers + cached + sReclaimable;
      }
      if (totalMem > 0) {
        float utilization = static_cast<float>(totalMem - availMem) / totalMem;
        if (std::abs(utilization - m_memoryUtilization) > 0.001f) {
          m_memoryUtilization = utilization;
          emit memoryUtilizationChanged();
        }
      }
    }
  }

  // Temperatures
  {
    QVariantList temps;
    QDir dir("/sys/class/thermal");
    QStringList filters;
    filters << "thermal_zone*";
    QStringList entries = dir.entryList(filters, QDir::Dirs);
    for (const QString &entry : entries) {
      QString type = "unknown";
      QFile typeFile(dir.absoluteFilePath(entry + "/type"));
      if (typeFile.open(QIODevice::ReadOnly)) {
        type = typeFile.readAll().trimmed();
      }

      QFile file(dir.absoluteFilePath(entry + "/temp"));
      if (file.open(QIODevice::ReadOnly)) {
        QTextStream stream(&file);
        bool ok;
        int temp = stream.readAll().trimmed().toInt(&ok);
        if (ok) {
          QVariantMap map;
          map["type"] = type;
          map["temp"] = static_cast<float>(temp) / 1000.0;
          temps.append(map);
        }
      }
    }
    if (temps != m_temperatures) {
      m_temperatures = temps;
      emit temperaturesChanged();
    }
  }
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

void Platform::refreshWiFiState() {
  bool hotspot = ::isHotspotEnabled();
  if (m_isHotspotEnabled != hotspot) {
    m_isHotspotEnabled = hotspot;
    emit isHotspotEnabledChanged(hotspot);
  }

  bool localHotspot = ::isLocalHotspotEnabled();
  if (m_isLocalHotspotEnabled != localHotspot) {
    m_isLocalHotspotEnabled = localHotspot;
    emit isLocalHotspotEnabledChanged(localHotspot);
  }

  emit hotspotIPAddressChanged();
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