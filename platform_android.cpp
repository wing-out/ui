
#include <qglobal.h>
#ifdef Q_OS_ANDROID
#include "platform.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QtCore/private/qandroidextras_p.h>

void Platform::vibrate(uint64_t duration_ms, bool is_notification) {
  QJniObject activity = QJniObject::callStaticObjectMethod(
      "org/qtproject/qt/android/QtNative", "activity",
      "()Landroid/app/Activity;");
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  uint32_t effect = 0xffffffff; // DEFAULT_AMPLITUDE
  if (!is_notification) {
    effect = 0x00000080;
  }

  QJniObject::callStaticMethod<void>("center/dx/wingout/VibratorWrapper",
                                     "vibrate", "(Landroid/content/Context;JI)V",
                                     activity.object<jobject>(),
                                     static_cast<jlong>(duration_ms), static_cast<jint>(effect));
}

void Platform::setEnableRunningInBackground(bool value) {
  auto activity = QJniObject(QNativeInterface::QAndroidApplication::context());
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }
  QAndroidIntent serviceIntent(activity.object(),
                               "center/dx/wingout/WingOutBackgroundService");
  QJniObject result = activity.callObjectMethod(
      "startService",
      "(Landroid/content/Intent;)Landroid/content/ComponentName;",
      serviceIntent.handle().object());
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

#endif
