
#ifdef Q_OS_ANDROID
#include "android.h"
#include <QCoreApplication>
#include <QJniObject>

void keepScreenOn() {
  QJniObject activity = QNativeInterface::QAndroidApplication::context();
  if (!activity.isValid()) {
    qWarning() << "unable to get the activity";
    return;
  }
  QJniObject window =
      activity.callObjectMethod("getWindow", "()Landroid/view/Window;");
  if (!window.isValid()) {
    qWarning() << "unable to get the window";
    return;
  }
  const int FLAG_KEEP_SCREEN_ON =
      128; // WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
  window.callMethod<void>("addFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
  qDebug() << "added the FLAG_KEEP_SCREEN_ON";
}

#endif
