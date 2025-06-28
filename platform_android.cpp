
#include <qglobal.h>
#ifdef Q_OS_ANDROID
#include "platform.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QtCore/private/qandroidextras_p.h>

void Platform::vibrate(uint64_t duration_ms) {
  QJniObject activity = QJniObject::callStaticObjectMethod(
      "org/qtproject/qt/android/QtNative", "activity",
      "()Landroid/app/Activity;");
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  QJniObject::callStaticMethod<void>("center/dx/wingout/VibratorWrapper",
                                     "vibrate", "(Landroid/content/Context;J)V",
                                     activity.object<jobject>(),
                                     static_cast<jlong>(duration_ms));
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
