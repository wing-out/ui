#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class MicrophoneController : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)

public:
    explicit MicrophoneController(QObject *parent = nullptr);

    QVariantList devices() const;
    Q_INVOKABLE void refresh();

signals:
    void devicesChanged();

private slots:
    void pollDevices();

private:
    QVariantList buildDevices() const;

    QVariantList m_devices; // list of QVariantMap{id: int, name: QString, type: int}
    QStringList m_lastDeviceIds;  // sorted ids of last emitted state, for change detection
    QTimer m_pollTimer;
};
