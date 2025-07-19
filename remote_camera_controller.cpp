
#include <QDebug>
#include <QMetaObject>
#include <QObject>
#include <QPermissions>
#include <QTimer>
#include <QtBluetooth/QBluetoothDeviceDiscoveryAgent>
#include <QtBluetooth/QBluetoothDeviceInfo>
#include <QtBluetooth/QLowEnergyController>
#include <QtBluetooth/QLowEnergyService>

#include "ble_remote_device.h"
#include "remote_camera_controller.h"

RemoteCameraController::RemoteCameraController() {
  discoveryAgent = new QBluetoothDeviceDiscoveryAgent(this);
  discoveryAgent->setLowEnergyDiscoveryTimeout(60000);
  connect(discoveryAgent, &QBluetoothDeviceDiscoveryAgent::deviceDiscovered,
          this, &RemoteCameraController::addDevice);
  connect(discoveryAgent, &QBluetoothDeviceDiscoveryAgent::errorOccurred, this,
          &RemoteCameraController::deviceScanError);
  connect(discoveryAgent, &QBluetoothDeviceDiscoveryAgent::finished, this,
          &RemoteCameraController::deviceScanFinished);
  connect(discoveryAgent, &QBluetoothDeviceDiscoveryAgent::canceled, this,
          &RemoteCameraController::deviceScanFinished);
  qDebug() << "searching";
}

RemoteCameraController::~RemoteCameraController() {
  qDeleteAll(devices);
  devices.clear();
}

void RemoteCameraController::startDeviceDiscovery() {
  qDebug() << "startDeviceDiscovery";
  qDeleteAll(devices);
  devices.clear();
  emit devicesUpdated();

  discoveryAgent->start(QBluetoothDeviceDiscoveryAgent::LowEnergyMethod);
  if (!discoveryAgent->isActive()) {
    return;
  }
  qDebug() << "unable to start";
}

void RemoteCameraController::stopDeviceDiscovery() {
  qDebug() << "stopDeviceDiscovery";
  if (discoveryAgent->isActive())
    discoveryAgent->stop();
}

void RemoteCameraController::addDevice(const QBluetoothDeviceInfo &info) {
  qDebug() << "addDevice: " << info.address();
  if (!info.coreConfigurations() &
      QBluetoothDeviceInfo::LowEnergyCoreConfiguration) {
    qWarning() << "device " << info.address() << " is not BLE";
    return;
  }
  auto devInfo = new BLERemoteDevice(info);
  auto it = std::find_if(devices.begin(), devices.end(),
                         [devInfo](BLERemoteDevice *dev) {
                           return devInfo->getAddress() == dev->getAddress();
                         });
  if (it != devices.end()) {
    auto oldDevice = *it;
    *it = devInfo;
    delete oldDevice;
    emit devicesUpdated();
    return;
  }
  devices.append(devInfo);
  emit devicesUpdated();
}

void RemoteCameraController::deviceScanFinished() {
  qDebug() << "deviceScanFinished";
}

void RemoteCameraController::deviceScanError(
    QBluetoothDeviceDiscoveryAgent::Error error) {
  qWarning() << "deviceScanError: " << error;
}

QVariant RemoteCameraController::getDevices() {
  return QVariant::fromValue(devices);
}