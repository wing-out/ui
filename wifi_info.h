#pragma once

#include <QObject>
#include <QString>
#include <qtmetamacros.h>

struct WiFiInfo {
    QString ssid;
    QString bssid;
    int rssi = 0;
    int signalPercent = 0;
    int frequency = 0;
};

class QWiFiInfo : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString ssid READ ssid CONSTANT)
  Q_PROPERTY(QString bssid READ bssid CONSTANT)
  Q_PROPERTY(int rssi READ rssi CONSTANT)                   // dBm
  Q_PROPERTY(int signalPercent READ signalPercent CONSTANT) // 0-100 %
  Q_PROPERTY(int frequency READ frequency CONSTANT)         // MHz

public:
  explicit QWiFiInfo(QObject *parent = nullptr);

  QWiFiInfo(const WiFiInfo, QObject *parent = nullptr);
  QWiFiInfo(const QString &ssid, const QString &bssid, int rssi = 0,
           int signalPercent = 0, int frequency = 0, QObject *parent = nullptr);
  QWiFiInfo(const QWiFiInfo &other);
  QWiFiInfo &operator=(const QWiFiInfo &other);

  void setFrom(const WiFiInfo &snapshot);

  QString ssid() const { return m_ssid; }
  QString bssid() const { return m_bssid; }
  int rssi() const { return m_rssi; }
  int signalPercent() const { return m_signalPercent; }
  int frequency() const { return m_frequency; }
  Q_INVOKABLE QString toJSON() const;

private:
  QString m_ssid;
  QString m_bssid;
  int m_rssi = 0;
  int m_signalPercent = 0;
  int m_frequency = 0;
};
