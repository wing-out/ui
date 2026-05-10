#pragma once

#include <QJSValue>
#include <QObject>
#include <QtQml/qqmlregistration.h>

#ifdef Q_OS_ANDROID
#include <QCoreApplication>
#include <QPermissions>
#include <QDebug>
#endif

// Free helpers used at app startup. They mirror Qt's QPermissions request
// flow for permissions that wingout always needs (Wi-Fi/BLE/Nearby) and
// are deliberately fire-and-forget — the user can still grant later via
// the OS Settings page.
#ifdef Q_OS_ANDROID
inline void androidEnsureWifiLocationPermission()
{
    QLocationPermission location;
    location.setAccuracy(QLocationPermission::Precise);
    location.setAvailability(QLocationPermission::WhenInUse);

    auto status = qApp->checkPermission(location);
    if (status == Qt::PermissionStatus::Granted)
        return;

    if (status == Qt::PermissionStatus::Denied) {
        qWarning() << "Location permission denied; Wi-Fi SSID/BSSID won't be available.";
        return;
    }

    qApp->requestPermission(location, [](const QPermission &perm) {
        if (perm.status() != Qt::PermissionStatus::Granted) {
            qWarning() << "User did not grant location permission; Wi-Fi info limited.";
        }
    });
}

inline void androidEnsureBluetoothPermission()
{
    QBluetoothPermission bluetooth;
    bluetooth.setCommunicationModes(QBluetoothPermission::Access);

    auto status = qApp->checkPermission(bluetooth);
    if (status == Qt::PermissionStatus::Granted)
        return;

    if (status == Qt::PermissionStatus::Denied) {
        qWarning() << "Bluetooth permission denied; BLE won't be available.";
        return;
    }

    qApp->requestPermission(bluetooth, [](const QPermission &perm) {
        if (perm.status() != Qt::PermissionStatus::Granted) {
            qWarning() << "User did not grant bluetooth permission; BLE info limited.";
        }
    });
}

#include <QJniObject>

inline void androidEnsureNearbyDevicesPermission()
{
    QJniObject activity = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative", "activity",
        "()Landroid/app/Activity;");
    if (activity.isValid()) {
        QJniObject::callStaticMethod<void>(
            "center/dx/wingout/WiFi", "requestNearbyDevicesPermission",
            "(Landroid/content/Context;)V", activity.object<jobject>());
    }
}
#endif // Q_OS_ANDROID

// AndroidPermissions exposes per-feature, on-demand permission requests
// to QML. Mirrors the QBluetoothPermission flow above but routes the
// outcome back to a JS callback so QML can chain follow-up work
// (e.g. ffstreamClient.addInput) on the granted path only.
//
// On non-Android platforms every request resolves synchronously with
// granted=true so desktop builds can drive the same QML chains.
class AndroidPermissions : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit AndroidPermissions(QObject *parent = nullptr) : QObject(parent) {}

    Q_INVOKABLE void requestRecordAudioPermission(QJSValue callback);
    Q_INVOKABLE void requestCameraPermission(QJSValue callback);
};
