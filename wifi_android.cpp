#include <qglobal.h>

#ifdef Q_OS_ANDROID
#include <QDebug>
#include <QJniObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <qobject.h>
#include <jni.h>

#include "wifi.h"

#define JAVA_WIFI_CLASS "center/dx/wingout/WiFi"

extern QJniObject getAndroidAppContext();

QString getCurrentWiFiConnectionJSON() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return "{}";
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return "{}";
  }

  QJniObject jsonStr = QJniObject::callStaticObjectMethod(
      JAVA_WIFI_CLASS, "getCurrentConnectionJSON",
      "(Landroid/content/Context;)Ljava/lang/String;",
      activity.object<jobject>());

  return jsonStr.toString();
}

QString getHotspotConfigurationJSON() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return "{}";
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return "{}";
  }

  QJniObject jsonStr = QJniObject::callStaticObjectMethod(
      JAVA_WIFI_CLASS, "getHotspotConfigurationJSON",
      "(Landroid/content/Context;)Ljava/lang/String;",
      activity.object<jobject>());

  return jsonStr.toString();
}

bool isHotspotEnabled() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return false;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return false;
  }

  return QJniObject::callStaticMethod<jboolean>(
      JAVA_WIFI_CLASS, "isHotspotEnabled", "(Landroid/content/Context;)Z",
      activity.object<jobject>());
}

void setHotspotEnabled(bool enabled) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  if (enabled) {
    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "requestNearbyDevicesPermission",
        "(Landroid/content/Context;)V", activity.object<jobject>());
  }

  QJniObject::callStaticMethod<void>(
      JAVA_WIFI_CLASS, "setHotspotEnabled", "(Landroid/content/Context;Z)V",
      activity.object<jobject>(), static_cast<jboolean>(enabled));
}

bool isLocalHotspotEnabled() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return false;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return false;
  }

  return QJniObject::callStaticMethod<jboolean>(
      JAVA_WIFI_CLASS, "isLocalHotspotEnabled", "(Landroid/content/Context;)Z",
      activity.object<jobject>());
}

void setLocalHotspotEnabled(bool enabled) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  if (enabled) {
    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "requestNearbyDevicesPermission",
        "(Landroid/content/Context;)V", activity.object<jobject>());
  }

  QJniObject::callStaticMethod<void>(
      JAVA_WIFI_CLASS, "setLocalHotspotEnabled", "(Landroid/content/Context;Z)V",
      activity.object<jobject>(), static_cast<jboolean>(enabled));
}

QString getLocalOnlyHotspotInfoJSON() {
  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return "{}";
  }

  QJniObject jsonStr = QJniObject::callStaticObjectMethod(
      JAVA_WIFI_CLASS, "getLocalOnlyHotspotInfoJSON",
      "()Ljava/lang/String;");

  return jsonStr.toString();
}

void saveHotspotConfiguration(const QString &ssid, const QString &psk) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  QJniObject jSsid = QJniObject::fromString(ssid);
  QJniObject jPsk = QJniObject::fromString(psk);

  QJniObject::callStaticMethod<void>(
      JAVA_WIFI_CLASS, "saveHotspotConfiguration",
      "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V",
      activity.object<jobject>(), jSsid.object<jstring>(),
      jPsk.object<jstring>());
}

WiFiInfo getCurrentWiFiConnection() {
  QString jsonStr = getCurrentWiFiConnectionJSON();
  const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
  if (!doc.isObject()) {
    qWarning() << "Current connection JSON is not an object";
    return WiFiInfo();
  }

  const QJsonObject o = doc.object();
  WiFiInfo result;
  result.ssid = o.value("ssid").toString();
  result.bssid = o.value("bssid").toString();
  result.rssi = o.value("rssi").toInt();
  result.frequency = o.value("frequency").toInt();
  return result;
}

void startWiFiScan() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  QJniObject::callStaticMethod<void>(JAVA_WIFI_CLASS, "startScan",
                                     "(Landroid/content/Context;)V",
                                     activity.object<jobject>());
}

QString getWiFiScanResultsJSON() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return "[]";
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return "[]";
  }

  QJniObject jsonStr = QJniObject::callStaticObjectMethod(
      JAVA_WIFI_CLASS, "getScanResultsJSON",
      "(Landroid/content/Context;)Ljava/lang/String;",
      activity.object<jobject>());

  return jsonStr.toString();
}

QVector<WiFiInfo> getWiFiScanResults() {
  QVector<WiFiInfo> out;

  QString json = getWiFiScanResultsJSON();
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isArray()) {
    qWarning() << "Scan results JSON is not an array";
    return out;
  }

  const QJsonArray arr = doc.array();
  out.reserve(arr.size());

  for (const QJsonValue &v : arr) {
    const QJsonObject o = v.toObject();
    WiFiInfo item;
    item.ssid = o.value("ssid").toString();
    item.bssid = o.value("bssid").toString();
    item.rssi = o.value("rssi").toInt();
    item.frequency = o.value("frequency").toInt();
    out.push_back(item);
  }
  return out;
}

int connectToWiFiAP(const QString &ssid, const QString &bssid,
                    const QString &security, const QString &password) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return -1;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return -1;
  }

  QJniObject jSsid = QJniObject::fromString(ssid);
  QJniObject jBssid = QJniObject::fromString(bssid);
  QJniObject jSec = QJniObject::fromString(security);
  QJniObject jPass = QJniObject::fromString(password);

  jint id = QJniObject::callStaticMethod<jint>(
      JAVA_WIFI_CLASS, "connectToAP",
      "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;Ljava/"
      "lang/String;Ljava/lang/String;)I",
      activity.object<jobject>(), jSsid.object<jstring>(),
      jBssid.object<jstring>(), jSec.object<jstring>(),
      jPass.object<jstring>());

  return static_cast<int>(id);
}

void disconnectRequestedWiFiAP(int requestId) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  QJniObject::callStaticMethod<void>(
      JAVA_WIFI_CLASS, "disconnectRequestedAP", "(Landroid/content/Context;I)V",
      activity.object<jobject>(), jint(requestId));
}

void disconnectAllRequestedWiFiAPs() {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
    qWarning() << "WiFi Java class not found";
    return;
  }

  QJniObject::callStaticMethod<void>(
      JAVA_WIFI_CLASS, "disconnectAllRequestedAPs",
      "(Landroid/content/Context;)V", activity.object<jobject>());
}
#endif
