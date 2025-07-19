

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
  qDebug() << "addService: " << serviceUUID;
  QLowEnergyService *service = controller->createServiceObject(serviceUUID);
  if (!service) {
    qWarning() << "Cannot create service for uuid";
    return;
  }
  auto serv = new BLEService(service);
  services.append(serv);
  emit servicesUpdated();
}

void BLERemoteDevice::servicesScanDone() { qDebug() << "servicesScanDone"; }

void BLERemoteDevice::discoverServiceDetails(const QString &uuid) {
  qDebug() << "discoverServiceDetails: " << uuid;
  BLEService *service = nullptr;
  for (auto svc : std::as_const(services)) {
    if (svc->getUUID() == uuid) {
      service = svc;
      break;
    }
  }
  if (!service) {
    qWarning() << "there is no service " << uuid;
    return;
  }

  qDeleteAll(characteristics);
  characteristics.clear();
  emit characteristicsUpdated();

  if (service->getQLowEnergyService()->state() != QLowEnergyService::RemoteService) {
    qWarning() << "service->state() != QLowEnergyService::RemoteService";
    return;
  }

  connect(service->getQLowEnergyService(), &QLowEnergyService::stateChanged, this,
          &BLERemoteDevice::serviceDetailsDiscovered);
  qDebug() << "service->discoverDetails()";
  service->getQLowEnergyService()->discoverDetails();
}

void BLERemoteDevice::serviceDetailsDiscovered(
    QLowEnergyService::ServiceState newState) {
  qDebug() << "serviceDetailsDiscovered: " << newState;
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

void BLERemoteDevice::errorReceived(QLowEnergyController::Error) {
  qWarning() << "Error: " << controller->errorString();
}

void BLERemoteDevice::deviceConnected() { qDebug() << "deviceConnected"; }

void BLERemoteDevice::deviceDisconnected() { qDebug() << "deviceDisconnected"; }

QVariant BLERemoteDevice::getServices() {
  return QVariant::fromValue(services);
}

QVariant BLERemoteDevice::getCharacteristics() {
  return QVariant::fromValue(characteristics);
}
