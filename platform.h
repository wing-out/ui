#pragma once

#include <QObject>
#include <QTime>
#include <QVariantMap>
#include <QtQml/qqmlengine.h>
#include <qtmetamacros.h>
#include <stdint.h>

#include "wifi.h"
#include "channel_quality_info.h"

class Platform : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_NAMED_ELEMENT(Platform)
  Q_PROPERTY(int signalStrength READ getSignalStrength WRITE setSignalStrength
                 NOTIFY onSignalStrengthChanged)
  Q_PROPERTY(bool isHotspotEnabled READ isHotspotEnabled WRITE setHotspotEnabled
                 NOTIFY isHotspotEnabledChanged)
  Q_PROPERTY(bool isLocalHotspotEnabled READ isLocalHotspotEnabled WRITE setLocalHotspotEnabled
                 NOTIFY isLocalHotspotEnabledChanged)
public:
  explicit Platform(QObject *parent = nullptr)
      : QObject(parent), m_currentWiFiConnection(new QWiFiInfo(this)), signalStrength(-1), m_isHotspotEnabled(false), m_isLocalHotspotEnabled(false) {}

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
  Q_INVOKABLE bool isHotspotEnabled();
  Q_INVOKABLE void setHotspotEnabled(bool enabled);
  Q_INVOKABLE bool isLocalHotspotEnabled();
  Q_INVOKABLE void setLocalHotspotEnabled(bool enabled);
  Q_INVOKABLE QVariantMap getLocalOnlyHotspotInfo();
  Q_INVOKABLE QVariantMap getHotspotConfiguration();
  Q_INVOKABLE void saveHotspotConfiguration(const QString &ssid, const QString &psk);
  Q_INVOKABLE void startWiFiScan();
  Q_INVOKABLE QVector<QWiFiInfo*> getWiFiScanResults();
  Q_INVOKABLE int connectToWiFiAP(const QString &ssid, const QString &bssid,
                                  const QString &security,
                                  const QString &password);
  Q_INVOKABLE void disconnectRequestedWiFiAP(int requestId);
  Q_INVOKABLE void disconnectAllRequestedWiFiAPs();

// Network:
  Q_INVOKABLE QList<QChannelQualityInfo*> getChannelsQualityInfo();

// UI:
  Q_INVOKABLE QVariantMap getSafeAreaInsets();

signals:
  void onSignalStrengthChanged(int strength);
  void isHotspotEnabledChanged(bool enabled);
  void isLocalHotspotEnabledChanged(bool enabled);

private:
  int signalStrength;
  bool m_isHotspotEnabled;
  bool m_isLocalHotspotEnabled;
  QWiFiInfo *m_currentWiFiConnection = nullptr;
  QList<QChannelQualityInfo*> m_channelsQualityInfo;
  QList<QWiFiInfo*> m_scanResults;
};
