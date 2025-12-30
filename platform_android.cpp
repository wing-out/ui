
#include <qglobal.h>

#ifdef Q_OS_ANDROID
#include "platform.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QtCore/private/qandroidextras_p.h>

QJniObject getAndroidAppContext() {
  return QJniObject::callStaticObjectMethod(
      "org/qtproject/qt/android/QtNative", "activity",
      "()Landroid/app/Activity;");
}

#include "wifi_android.cpp"

void Platform::vibrate(uint64_t duration_ms, bool is_notification) {
  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  uint32_t effect = 0xffffffff; // DEFAULT_AMPLITUDE
  if (!is_notification) {
    effect = 0x00000080;
  }

  QJniObject::callStaticMethod<void>(
      "center/dx/wingout/VibratorWrapper", "vibrate",
      "(Landroid/content/Context;JI)V", activity.object<jobject>(),
      static_cast<jlong>(duration_ms), static_cast<jint>(effect));
}

void Platform::setEnableRunningInBackground(bool value) {
  return;
  /*
  auto activity = getAndroidAppContext();
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }
  QAndroidIntent serviceIntent(activity.object(),
                               "center/dx/wingout/WingOutBackgroundService");
  QJniObject result = activity.callObjectMethod(
      "startService",
      "(Landroid/content/Intent;)Landroid/content/ComponentName;",
      serviceIntent.handle().object());*/
}

void Platform::startMonitoringSignalStrength() {
  QNativeInterface::QAndroidApplication::runOnAndroidMainThread([=]() {
    QJniObject activity =
        QJniObject(QNativeInterface::QAndroidApplication::context());
    QJniObject::callStaticMethod<void>(
        "center/dx/wingout/SignalStrengthListener", "init",
        "(Landroid/app/Activity;)V", activity.object<jobject>());
    QJniObject::callStaticMethod<void>(
        "center/dx/wingout/SignalStrengthListener",
        "installSignalStrengthListener", "()V");
  });
}

extern QList<ChannelQualityInfo>
parseFileWithChannelsQuality(const QString &filePath);
QList<ChannelQualityInfo> getChannelsQualityInfo() {
  return parseFileWithChannelsQuality("/data/user/0/center.dx.wingout/files/channel-quality.txt");
}

QVariantMap Platform::getSafeAreaInsets() {
  QVariantMap insets;
  insets["top"] = 0;
  insets["bottom"] = 0;
  insets["left"] = 0;
  insets["right"] = 0;

  QJniObject activity = getAndroidAppContext();
  if (!activity.isValid()) {
    return insets;
  }

  QJniObject window =
      activity.callObjectMethod("getWindow", "()Landroid/view/Window;");
  if (!window.isValid()) {
    return insets;
  }

  QJniObject decorView =
      window.callObjectMethod("getDecorView", "()Landroid/view/View;");
  if (!decorView.isValid()) {
    return insets;
  }

  QJniObject rootWindowInsets = decorView.callObjectMethod(
      "getRootWindowInsets", "()Landroid/view/WindowInsets;");
  if (!rootWindowInsets.isValid()) {
    return insets;
  }

  // Type.systemBars() is 7 (statusBars | navigationBars | captionBar)
  QJniObject systemBarsInsets = rootWindowInsets.callObjectMethod(
      "getInsets", "(I)Landroid/graphics/Insets;", 7);
  if (systemBarsInsets.isValid()) {
    insets["top"] = systemBarsInsets.getField<jint>("top");
    insets["bottom"] = systemBarsInsets.getField<jint>("bottom");
    insets["left"] = systemBarsInsets.getField<jint>("left");
    insets["right"] = systemBarsInsets.getField<jint>("right");
  }

  QJniObject displayCutout = rootWindowInsets.callObjectMethod(
      "getDisplayCutout", "()Landroid/view/DisplayCutout;");
  if (displayCutout.isValid()) {
    insets["top"] =
        qMax(insets["top"].toInt(), displayCutout.callMethod<jint>("getSafeInsetTop"));
    insets["bottom"] = qMax(insets["bottom"].toInt(),
                            displayCutout.callMethod<jint>("getSafeInsetBottom"));
    insets["left"] = qMax(insets["left"].toInt(),
                          displayCutout.callMethod<jint>("getSafeInsetLeft"));
    insets["right"] = qMax(insets["right"].toInt(),
                           displayCutout.callMethod<jint>("getSafeInsetRight"));
  }

  return insets;
}

#endif
