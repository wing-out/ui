
#include <qglobal.h>
#ifdef Q_OS_ANDROID
#include "platform.h"

#include <QCoreApplication>
#include <QJniObject>

void Platform::vibrate(uint64_t duration_ms) {
  QJniObject activity = QJniObject::callStaticObjectMethod(
      "org/qtproject/qt/android/QtNative", "activity",
      "()Landroid/app/Activity;");
  if (!activity.isValid()) {
    qWarning() << "unable to find the activity";
    return;
  }

  QJniObject::callStaticMethod<void>(
      "center/dx/wingout/VibratorWrapper", "vibrate", "(Landroid/content/Context;J)V",
      activity.object<jobject>(), static_cast<jlong>(duration_ms));
}
#endif
