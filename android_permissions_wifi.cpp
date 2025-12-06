#ifdef Q_OS_ANDROID

#pragma once

#include <QCoreApplication>
#include <QPermissions>

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

    // Undetermined -> trigger runtime dialog
    qApp->requestPermission(location, [](const QPermission &perm) {
        if (perm.status() != Qt::PermissionStatus::Granted) {
            qWarning() << "User did not grant location permission; Wi-Fi info limited.";
        }
    });
}

#endif