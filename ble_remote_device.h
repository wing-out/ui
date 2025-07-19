
#ifndef BLE_DEVICE_H
#define BLE_DEVICE_H

#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QtBluetooth/QBluetoothAddress>
#include <QtBluetooth/QBluetoothDeviceInfo>
#include <QtBluetooth/QLowEnergyController>
#include <qtmetamacros.h>

#include "ble_characteristic.h"
#include "ble_service.h"

class BLERemoteDevice : public QObject, QBluetoothDeviceInfo {
  Q_OBJECT
  Q_PROPERTY(QVariant services READ getServices NOTIFY servicesUpdated)
  Q_PROPERTY(QVariant characteristics READ getCharacteristics NOTIFY
                 characteristicsUpdated)

public:
  BLERemoteDevice(const QBluetoothDeviceInfo &d, QObject *parent = nullptr);
  QBluetoothDeviceInfo getQBluetoothDeviceInfo() const {
    QBluetoothDeviceInfo devInfo;
    devInfo = *this;
    return devInfo;
  }
  QString getAddress() const { return this->address().toString(); }
  QString getName() const { return this->name(); };
  QVariant getServices();
  QVariant getCharacteristics();
  void scanServices();
  void discoverServiceDetails(const QString &uuid);

private slots:
  void addService(const QBluetoothUuid &serviceUUID);
  void errorReceived(QLowEnergyController::Error);
  void deviceConnected();
  void deviceDisconnected();
  void serviceDetailsDiscovered(QLowEnergyService::ServiceState newState);
  void servicesScanDone();

signals:
  void servicesUpdated();
  void characteristicsUpdated();

private:
  QList<BLECharacteristic *> characteristics;
  QList<BLEService *> services;
  QLowEnergyController *controller;
};

#endif // BLE_DEVICE_H
