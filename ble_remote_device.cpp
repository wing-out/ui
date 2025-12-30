

#include <QObject>
#include <QTimer>
#include <QVariant>
#include <QtBluetooth/QLowEnergyController>

#include "ble_remote_device.h"
#include "ble_service.h"

BLERemoteDevice::BLERemoteDevice(const QBluetoothDeviceInfo &d, QObject *parent)
    : QBluetoothDeviceInfo(d), QObject(parent) {
  controller = QLowEnergyController::createCentral(d);
  connect(controller, &QLowEnergyController::connected, this,
          &BLERemoteDevice::deviceConnected);
  connect(controller, &QLowEnergyController::errorOccurred, this,
          &BLERemoteDevice::errorReceived);
  connect(controller, &QLowEnergyController::disconnected, this,
          &BLERemoteDevice::deviceDisconnected);
  connect(controller, &QLowEnergyController::serviceDiscovered, this,
          &BLERemoteDevice::addService);
  connect(controller, &QLowEnergyController::discoveryFinished, this,
          &BLERemoteDevice::servicesScanDone);
}

void BLERemoteDevice::addService(const QBluetoothUuid &serviceUUID) {
  qDebug() << "[DJI-BLE] addService: " << serviceUUID.toString();
  QLowEnergyService *service = controller->createServiceObject(serviceUUID);
  if (!service) {
    qWarning() << "[DJI-BLE] Cannot create service for uuid";
    return;
  }
  auto serv = new BLEService(service);
  services.append(serv);
  emit servicesUpdated();
}

void BLERemoteDevice::servicesScanDone() { qDebug() << "[DJI-BLE] " << "servicesScanDone"; }

void BLERemoteDevice::scanServices() {
  qDebug() << "[DJI-BLE] scanServices";
  controller->connectToDevice();
}

bool BLERemoteDevice::getConnected() const {
  return controller && controller->state() == QLowEnergyController::ConnectedState;
}

void BLERemoteDevice::connectToDevice() {
  if (controller) {
    if (controller->state() != QLowEnergyController::UnconnectedState) {
      qDebug() << "[DJI-BLE] Already connecting or connected, state:" << controller->state();
      return;
    }
    controller->connectToDevice();
  }
}

void BLERemoteDevice::discoverServiceDetails(const QString &uuid) {
  qDebug() << "[DJI-BLE] discoverServiceDetails: " << uuid;
  BLEService *service = nullptr;
  for (auto svc : std::as_const(services)) {
    if (svc->getUUID() == uuid) {
      service = svc;
      break;
    }
  }
  if (!service) {
    qWarning() << "[DJI-BLE] there is no service " << uuid;
    return;
  }

  qDeleteAll(characteristics);
  characteristics.clear();
  emit characteristicsUpdated();

  if (service->getQLowEnergyService()->state() != QLowEnergyService::RemoteService) {
    qWarning() << "[DJI-BLE] service->state() != QLowEnergyService::RemoteService";
    return;
  }

  connect(service->getQLowEnergyService(), &QLowEnergyService::stateChanged, this,
          &BLERemoteDevice::serviceDetailsDiscovered);
  qDebug() << "[DJI-BLE] service->discoverDetails()";
  service->getQLowEnergyService()->discoverDetails();
}

void BLERemoteDevice::serviceDetailsDiscovered(
    QLowEnergyService::ServiceState newState) {
  qDebug() << "[DJI-BLE] serviceDetailsDiscovered: " << newState;
  auto service = qobject_cast<QLowEnergyService *>(sender());
  if (!service)
    return;

  const QList<QLowEnergyCharacteristic> chars = service->characteristics();
  for (const QLowEnergyCharacteristic &ch : chars) {
    auto cInfo = new BLECharacteristic(ch);
    characteristics.append(cInfo);
  }

  emit characteristicsUpdated();
}

void BLERemoteDevice::errorReceived(QLowEnergyController::Error err) {
  qWarning() << "[DJI-BLE] Controller Error: " << err << controller->errorString();
}

void BLERemoteDevice::deviceConnected() {
  qDebug() << "[DJI-BLE] deviceConnected to" << this->name() << this->address().toString();
  
  // Try to set connection parameters for stability
  QLowEnergyConnectionParameters params;
  params.setIntervalRange(20, 40);
  params.setLatency(0);
  params.setSupervisionTimeout(10000);
  controller->requestConnectionUpdate(params);

  connect(controller, &QLowEnergyController::mtuChanged, this, [](int mtu) {
      qDebug() << "[DJI-BLE] MTU changed to" << mtu;
  });

  QTimer::singleShot(2000, controller, [this]() {
      qDebug() << "[DJI-BLE] starting discoverServices";
      controller->discoverServices();
  });
}

void BLERemoteDevice::deviceDisconnected() { 
    qDebug() << "[DJI-BLE] deviceDisconnected" << this->address().toString();
}

QVariant BLERemoteDevice::getServices() {
  return QVariant::fromValue(services);
}

QVariant BLERemoteDevice::getCharacteristics() {
  return QVariant::fromValue(characteristics);
}
