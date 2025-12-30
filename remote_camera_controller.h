#ifndef REMOTE_CAMERA_CONTROLLER_H
#define REMOTE_CAMERA_CONTROLLER_H

#include <QObject>
#include <QVariant>

class RemoteCameraController : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariant devicesList READ getDevices NOTIFY devicesUpdated)
  Q_PROPERTY(QString deviceNameFilter READ deviceNameFilter WRITE setDeviceNameFilter NOTIFY deviceNameFilterChanged)
  Q_PROPERTY(QString deviceAddressFilter READ deviceAddressFilter WRITE setDeviceAddressFilter NOTIFY deviceAddressFilterChanged)

public:
  using QObject::QObject;
  virtual ~RemoteCameraController() = default;

  virtual QVariant getDevices() = 0;
  virtual QString deviceNameFilter() const = 0;
  virtual void setDeviceNameFilter(const QString &filter) = 0;
  virtual QString deviceAddressFilter() const = 0;
  virtual void setDeviceAddressFilter(const QString &filter) = 0;

public slots:
  virtual void startDeviceDiscovery() = 0;
  virtual void stopDeviceDiscovery() = 0;

signals:
  void devicesUpdated();
  void deviceScanFinished();
  void deviceScanError(const QString &msg);
  void deviceNameFilterChanged();
  void deviceAddressFilterChanged();
};

#endif
