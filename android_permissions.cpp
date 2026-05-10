#include "android_permissions.h"

#include <QCoreApplication>
#include <QDebug>

#ifdef Q_OS_ANDROID
#include <QPermissions>
#endif

namespace {

// Helper: invoke a QJSValue callback with a single bool argument iff it is
// callable. Mirrors the pattern used by ffstream_client.cpp for its
// finishCallback / errorCallback dispatch.
inline void invokeBoolCallback(QJSValue cb, bool granted) {
    if (!cb.isCallable()) {
        return;
    }
    QJSValueList args;
    args << QJSValue(granted);
    cb.call(args);
}

#ifdef Q_OS_ANDROID
template <typename Permission>
void requestSimplePermission(QJSValue callback, const char *label) {
    Permission perm;

    auto status = qApp->checkPermission(perm);
    if (status == Qt::PermissionStatus::Granted) {
        invokeBoolCallback(callback, true);
        return;
    }
    if (status == Qt::PermissionStatus::Denied) {
        qWarning() << label << "permission was previously denied; surfacing"
                   << "denial to QML so the user can be prompted to enable it"
                   << "via Settings.";
        invokeBoolCallback(callback, false);
        return;
    }

    // Undetermined -> trigger runtime dialog.
    qApp->requestPermission(perm, [callback, label](const QPermission &p) mutable {
        const bool granted = (p.status() == Qt::PermissionStatus::Granted);
        if (!granted) {
            qWarning() << "User did not grant" << label << "permission.";
        }
        invokeBoolCallback(callback, granted);
    });
}
#endif // Q_OS_ANDROID

} // namespace

void AndroidPermissions::requestRecordAudioPermission(QJSValue callback) {
#ifdef Q_OS_ANDROID
    requestSimplePermission<QMicrophonePermission>(callback, "RECORD_AUDIO");
#else
    // Desktop / other platforms: assume the OS already gates capture and
    // synchronously report success so QML chains keep working.
    invokeBoolCallback(callback, true);
#endif
}

void AndroidPermissions::requestCameraPermission(QJSValue callback) {
#ifdef Q_OS_ANDROID
    requestSimplePermission<QCameraPermission>(callback, "CAMERA");
#else
    invokeBoolCallback(callback, true);
#endif
}
