
#ifndef BLE_SERVICE_H
#define BLE_SERVICE_H

#include <QObject>
#include <QQmlEngine>
#include <QtBluetooth/QLowEnergyService>

class BLEService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString name READ getName NOTIFY changed)
    Q_PROPERTY(QString uuid READ getUUID NOTIFY changed)

public:
    BLEService(QLowEnergyService* s, QObject* parent = nullptr)
        : QObject(parent), service(s) {
        connect(service, &QLowEnergyService::stateChanged, this, &BLEService::changed);
    }

    QLowEnergyService* getQLowEnergyService() const {
        return service;
    }

    QString getUUID() const {
        return service ? service->serviceUuid().toString() : QString{};
    }

    QString getName() const {
        return service ? service->serviceName() : QString{};
    }

Q_SIGNALS:
    void changed();

private:
    QLowEnergyService* service;
};

#endif // BLE_SERVICE_H
