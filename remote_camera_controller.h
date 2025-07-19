#ifndef REMOTE_CAMERA_CONTROLLER_H
#define REMOTE_CAMERA_CONTROLLER_H

#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QVariant>
#include <QtBluetooth/QBluetoothDeviceDiscoveryAgent>
#include <QtBluetooth/QBluetoothDeviceInfo>
#include <QtBluetooth/QLowEnergyController>
#include <QtBluetooth/QLowEnergyService>

#include "ble_remote_device.h"

class RemoteCameraController : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON
  Q_PROPERTY(QVariant devicesList READ getDevices NOTIFY devicesUpdated)

public:
  RemoteCameraController();
  ~RemoteCameraController();
  QVariant getDevices();
  QString getUpdate();

public slots:
  void startDeviceDiscovery();
  void stopDeviceDiscovery();

private slots:
  void addDevice(const QBluetoothDeviceInfo &);
  void deviceScanFinished();
  void deviceScanError(QBluetoothDeviceDiscoveryAgent::Error);

signals:
  void devicesUpdated();

private:
  QBluetoothDeviceDiscoveryAgent *discoveryAgent;
  BLERemoteDevice *currentDevice = nullptr;
  QList<BLERemoteDevice *> devices;
};

#endif // REMOTE_CAMERA_CONTROLLER_H
