
#include "wifi_info.h"

void QWiFiInfo::setFrom(const WiFiInfo &snapshot)
{
    m_ssid          = snapshot.ssid;
    m_bssid         = snapshot.bssid;
    m_rssi          = snapshot.rssi;
    m_signalPercent = snapshot.signalPercent;
    m_frequency     = snapshot.frequency;
}

QWiFiInfo::QWiFiInfo(QObject *parent) : QObject(parent) {}

QWiFiInfo::QWiFiInfo(const WiFiInfo snapshot, QObject *parent)
    : QObject(parent) {
  setFrom(snapshot);
}

QWiFiInfo::QWiFiInfo(const QString &ssid, const QString &bssid, int rssi,
                   int signalPercent, int frequency, QObject *parent)
    : QObject(parent), m_ssid(ssid), m_bssid(bssid), m_rssi(rssi),
      m_signalPercent(signalPercent), m_frequency(frequency) {}

QWiFiInfo::QWiFiInfo(const QWiFiInfo &other)
    : QObject(other.parent()), m_ssid(other.m_ssid), m_bssid(other.m_bssid),
      m_rssi(other.m_rssi), m_signalPercent(other.m_signalPercent),
      m_frequency(other.m_frequency) {}

QWiFiInfo &QWiFiInfo::operator=(const QWiFiInfo &other) {
  if (this != &other) {
    // Do NOT touch QObject internals; just copy our data.
    m_ssid = other.m_ssid;
    m_bssid = other.m_bssid;
    m_rssi = other.m_rssi;
    m_signalPercent = other.m_signalPercent;
    m_frequency = other.m_frequency;
  }
  return *this;
}

QString QWiFiInfo::toJSON() const {
  return QString("{\"ssid\":\"%1\",\"bssid\":\"%2\",\"rssi\":%3,"
                 "\"signalPercent\":%4,\"frequency\":%5}")
      .arg(m_ssid)
      .arg(m_bssid)
      .arg(m_rssi)
      .arg(m_signalPercent)
      .arg(m_frequency);
}
