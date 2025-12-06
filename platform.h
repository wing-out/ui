#pragma once

#include <QObject>
#include <QTime>
#include <QtQml/qqmlengine.h>
#include <qtmetamacros.h>

#include "wifi.h"

class Platform : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_NAMED_ELEMENT(Platform)
  Q_PROPERTY(int signalStrength READ getSignalStrength WRITE setSignalStrength
                 NOTIFY onSignalStrengthChanged)
public:
  explicit Platform(QObject *parent = nullptr)
      : QObject(parent), m_currentWiFiConnection(new QWiFiInfo(this)) , signalStrength(-1) {}

// Power management:
  Q_INVOKABLE void setEnableRunningInBackground(bool value);

// Vibrate:
  Q_INVOKABLE void vibrate(uint64_t duration_ms, bool is_notification);

// Mobile:
  Q_INVOKABLE void startMonitoringSignalStrength();
  Q_INVOKABLE int getSignalStrength() { return signalStrength; }
  void setSignalStrength(int strength) {
    if (signalStrength != strength) {
      signalStrength = strength;
      emit onSignalStrengthChanged(strength);
    }
  }

// WiFi:
  Q_INVOKABLE QWiFiInfo *getCurrentWiFiConnection();
  Q_INVOKABLE void startWiFiScan();
  Q_INVOKABLE QVector<QWiFiInfo*> getWiFiScanResults();
  Q_INVOKABLE int connectToWiFiAP(const QString &ssid, const QString &bssid,
                                  const QString &security,
                                  const QString &password);
  Q_INVOKABLE void disconnectRequestedWiFiAP(int requestId);
  Q_INVOKABLE void disconnectAllRequestedWiFiAPs();

signals:
  void onSignalStrengthChanged(int strength);

private:
  int signalStrength;
  QWiFiInfo *m_currentWiFiConnection = nullptr;
  QList<QWiFiInfo*> m_scanResults;
};
