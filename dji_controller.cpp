#include "dji_controller.h"
#include "dji/device_flow.h"
#include <QDebug>

DJIController::DJIController(QObject *parent) : RemoteCameraController(parent) {
    m_manager = new dji::DeviceManager(nullptr, this);
    
    connect(m_manager, &dji::DeviceManager::devicesChanged, this, &DJIController::devicesUpdated);
    connect(m_manager, &dji::DeviceManager::error, this, &DJIController::error);
    connect(m_manager, &dji::DeviceManager::log, this, &DJIController::log);
    
    connect(m_manager, &dji::DeviceManager::isPairedChanged, this, [this](dji::Device *dev) {
        if (dev == m_device) emit isPairedChanged();
    });
    connect(m_manager, &dji::DeviceManager::isWiFiConnectedChanged, this, [this](dji::Device *dev) {
        if (dev == m_device) emit isWiFiConnectedChanged();
    });
    connect(m_manager, &dji::DeviceManager::isStreamingChanged, this, [this](dji::Device *dev) {
        if (dev == m_device) emit isStreamingChanged();
    });
}

QVariant DJIController::getDevices() {
    QList<QObject *> list;
    for (auto dev : m_manager->devices()) {
        list.append(dev);
    }
    return QVariant::fromValue(list);
}

void DJIController::startDeviceDiscovery() {
    dji::DiscoveryOptions opt;
    opt.deviceNameFilter = m_deviceNameFilter;
    opt.deviceAddrFilter = m_deviceAddressFilter;
    m_manager->startDiscovery(opt);
}

void DJIController::stopDeviceDiscovery() {
    m_manager->stopDiscovery();
}

void DJIController::setDeviceNameFilter(const QString &filter) {
    if (m_deviceNameFilter != filter) {
        m_deviceNameFilter = filter;
        emit deviceNameFilterChanged();
    }
}

void DJIController::setDeviceAddressFilter(const QString &filter) {
    if (m_deviceAddressFilter != filter) {
        m_deviceAddressFilter = filter;
        emit deviceAddressFilterChanged();
    }
}

void DJIController::setDevice(dji::Device* device) {
    if (m_device != device) {
        m_device = device;
        emit deviceChanged();
        emit isPairedChanged();
        emit isWiFiConnectedChanged();
        emit isStreamingChanged();
    }
}

bool DJIController::isPaired() const {
    return m_device && m_device->isInitialized();
}

bool DJIController::isWiFiConnected() const {
    return m_device && m_device->isConnected();
}

bool DJIController::isStreaming() const {
    return m_manager->isStreaming();
}

void DJIController::setWifiSSID(const QString &ssid) {
    if (m_wifiSSID != ssid) {
        m_wifiSSID = ssid;
        emit wifiSSIDChanged();
    }
}

void DJIController::setWifiPSK(const QString &psk) {
    if (m_wifiPSK != psk) {
        m_wifiPSK = psk;
        emit wifiPSKChanged();
    }
}

void DJIController::startStreaming(const QString &rtmpUrl, int resolution, int fps, int bitrateKbps) {
    if (!m_device) {
        emit error("No device selected");
        return;
    }

    dji::StreamingOptions opt;
    opt.rtmpUrl = rtmpUrl;
    opt.ssid = m_wifiSSID;
    opt.psk = m_wifiPSK;
    opt.resolution = static_cast<dji::Resolution>(resolution == 1080 ? dji::Resolution::Res1080p : (resolution == 720 ? dji::Resolution::Res720p : dji::Resolution::Res480p));
    opt.fps = static_cast<dji::FPS>(fps == 30 ? dji::FPS::FPS30 : dji::FPS::FPS25);
    opt.bitrateKbps = static_cast<uint16_t>(bitrateKbps);

    m_manager->runFlow(m_device, new dji::StreamingStarter(opt, this));
}

void DJIController::stopStreaming() {
    m_manager->stop();
}
