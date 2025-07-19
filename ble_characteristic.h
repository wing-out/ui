
#ifndef BLE_CHARACTERISTIC_H
#define BLE_CHARACTERISTIC_H

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QtBluetooth/QLowEnergyCharacteristic>

class BLECharacteristic : public QObject, QLowEnergyCharacteristic {
  Q_OBJECT
  Q_PROPERTY(QString name READ getName NOTIFY changed)
  Q_PROPERTY(QString uuid READ getUUID NOTIFY changed)

public:
  BLECharacteristic(const QLowEnergyCharacteristic &c, QObject *parent = nullptr)
      : QObject(parent), QLowEnergyCharacteristic(c) {};
  QString getName() const {
    QString _name = this->name();
    if (!_name.isEmpty())
      return _name;

    const QList<QLowEnergyDescriptor> descriptors = this->descriptors();
    for (const QLowEnergyDescriptor &descriptor : descriptors) {
      if (descriptor.type() ==
          QBluetoothUuid::DescriptorType::CharacteristicUserDescription) {
        return descriptor.value();
      }
    }

    return "";
  }
  QString getUUID() const { return uuid().toString(); };

Q_SIGNALS:
  void changed();
};

#endif // BLE_CHARACTERISTIC_H
