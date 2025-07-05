
#include <qglobal.h>

#ifdef Q_OS_ANDROID
#define _PLATFORM_IS_SET
#include "platform_android.cpp"
#endif

#ifdef _PLATFORM_IS_SET
#undef _PLATFORM_IS_SET
#else
#include "platform.h"
void Platform::vibrate(uint64_t duration_ms, bool is_notification) {}
void Platform::setEnableRunningInBackground(bool value) {}
void Platform::startMonitoringSignalStrength() {}
#endif
