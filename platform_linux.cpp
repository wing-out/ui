#include <qcontainerfwd.h>
#include <qglobal.h>

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QVariant>

#include "platform.h"

#include "wifi_linux.cpp"

void Platform::vibrate(uint64_t duration_ms, bool is_notification) { return; }

void Platform::setEnableRunningInBackground(bool value) { return; }

void Platform::startMonitoringSignalStrength() { return; }

extern QList<ChannelQualityInfo>
parseFileWithChannelsQuality(const QString &filePath);
QList<ChannelQualityInfo> getChannelsQualityInfo() {
  return parseFileWithChannelsQuality("/tmp/quality");
}

#endif