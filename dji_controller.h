/**
 * @file dji_controller.h
 * @brief QML-exposed controller for DJI devices in the wingout application.
 */

#ifndef DJI_CONTROLLER_H
#define DJI_CONTROLLER_H

#include "remote_camera_controller.h"
#include "dji/device.h"
#include "dji/device_manager.h"
#include <QQmlEngine>

class DJIController : public RemoteCameraController {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(dji::Device* device READ device WRITE setDevice NOTIFY deviceChanged)
    Q_PROPERTY(bool isPaired READ isPaired NOTIFY isPairedChanged)
    Q_PROPERTY(bool isWiFiConnected READ isWiFiConnected NOTIFY isWiFiConnectedChanged)
    Q_PROPERTY(bool isStreaming READ isStreaming NOTIFY isStreamingChanged)
    Q_PROPERTY(QString wifiSSID READ wifiSSID WRITE setWifiSSID NOTIFY wifiSSIDChanged)
    Q_PROPERTY(QString wifiPSK READ wifiPSK WRITE setWifiPSK NOTIFY wifiPSKChanged)

public:
    explicit DJIController(QObject *parent = nullptr);

    // RemoteCameraController implementation
    QVariant getDevices() override;
    void startDeviceDiscovery() override;
    void stopDeviceDiscovery() override;
    QString deviceNameFilter() const override { return m_deviceNameFilter; }
    void setDeviceNameFilter(const QString &filter) override;
    QString deviceAddressFilter() const override { return m_deviceAddressFilter; }
    void setDeviceAddressFilter(const QString &filter) override;

    // DJI specific
    dji::Device* device() const { return m_device; }
    void setDevice(dji::Device* device);

    bool isPaired() const;
    bool isWiFiConnected() const;
    bool isStreaming() const;

    QString wifiSSID() const { return m_wifiSSID; }
    void setWifiSSID(const QString &ssid);
    QString wifiPSK() const { return m_wifiPSK; }
    void setWifiPSK(const QString &psk);

    Q_INVOKABLE void startStreaming(const QString &rtmpUrl, int resolution, int fps, int bitrateKbps);
    Q_INVOKABLE void stopStreaming();

signals:
    void deviceChanged();
    void isPairedChanged();
    void isWiFiConnectedChanged();
    void isStreamingChanged();
    void wifiSSIDChanged();
    void wifiPSKChanged();
    void error(const QString &message);
    void log(const QString &message);

private:
    dji::DeviceManager* m_manager;
    dji::Device* m_device = nullptr;
    QString m_wifiSSID;
    QString m_wifiPSK;
    QString m_deviceNameFilter;
    QString m_deviceAddressFilter;
};

#endif
