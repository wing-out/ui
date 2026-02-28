#include "djicontroller.h"
#include <QDateTime>
#include <QDebug>
#include <QtEndian>

// ---------------------------------------------------------------------------
// CRC tables (same polynomial and init values as libdji)
// ---------------------------------------------------------------------------

static constexpr uint8_t CRC8_POLY_REV = 0x8C;
static constexpr uint8_t CRC8_INIT = 0x77;
static constexpr uint16_t CRC16_POLY_REV = 0x8408;
static constexpr uint16_t CRC16_INIT = 0x3692;

uint8_t DJIController::crc8(const QByteArray &data)
{
    uint8_t crc = CRC8_INIT;
    for (char c : data) {
        crc ^= static_cast<uint8_t>(c);
        for (int i = 0; i < 8; ++i) {
            if (crc & 1)
                crc = (crc >> 1) ^ CRC8_POLY_REV;
            else
                crc >>= 1;
        }
    }
    return crc;
}

uint16_t DJIController::crc16(const QByteArray &data)
{
    uint16_t crc = CRC16_INIT;
    for (char c : data) {
        crc ^= static_cast<uint8_t>(c);
        for (int i = 0; i < 8; ++i) {
            if (crc & 1)
                crc = (crc >> 1) ^ CRC16_POLY_REV;
            else
                crc >>= 1;
        }
    }
    return crc;
}

// ---------------------------------------------------------------------------
// String packing helpers (same wire format as libdji)
// ---------------------------------------------------------------------------

QByteArray DJIController::packString(const QString &s)
{
    QByteArray res;
    QByteArray utf8 = s.toUtf8();
    uint8_t len = static_cast<uint8_t>(utf8.length());
    res.append(static_cast<char>(len));
    res.append(utf8);
    return res;
}

QByteArray DJIController::packURL(const QString &s)
{
    QByteArray res;
    QByteArray utf8 = s.toUtf8();
    uint16_t len = qToLittleEndian<uint16_t>(static_cast<uint16_t>(utf8.length()));
    res.append(reinterpret_cast<const char *>(&len), 2);
    res.append(utf8);
    return res;
}

QString DJIController::unpackStringU16BE(const QByteArray &data)
{
    if (data.size() < 2)
        return {};
    uint16_t len = qFromBigEndian<uint16_t>(reinterpret_cast<const uchar *>(data.data()));
    if (data.size() < 2 + len)
        return {};
    return QString::fromUtf8(data.mid(2, len));
}

// ---------------------------------------------------------------------------
// Device type identification from BLE manufacturer data
// ---------------------------------------------------------------------------

DJIController::DJIDeviceType DJIController::identifyDeviceType(const QByteArray &manufacturerData)
{
    if (manufacturerData.size() < 4)
        return DJIDeviceType::Unknown;
    uint8_t typeByte = static_cast<uint8_t>(manufacturerData[2]);
    switch (typeByte) {
    case 0x15: return DJIDeviceType::OsmoAction5Pro;
    case 0x14: return DJIDeviceType::OsmoAction4;
    case 0x20: return DJIDeviceType::OsmoPocket3;
    default:   return DJIDeviceType::Unknown;
    }
}

uint8_t DJIController::deviceTypeToByte(DJIDeviceType t)
{
    switch (t) {
    case DJIDeviceType::OsmoAction5Pro: return 0x2E;
    default:                            return 0x2A;
    }
}

// ---------------------------------------------------------------------------
// DJIMessage serialization (wire format: 0x55 | len(10-bit) | version | crc8 | ...)
// ---------------------------------------------------------------------------

QByteArray DJIController::DJIMessage::serialize() const
{
    const uint16_t headersAndTail = 13;

    QByteArray buf;
    buf.append(static_cast<char>(0x55));

    uint16_t length = static_cast<uint16_t>(payload.size() + headersAndTail);
    buf.append(static_cast<char>(length & 0xFF));
    buf.append(static_cast<char>((0x01 << 2) | ((length >> 8) & 0x03)));

    buf.append(static_cast<char>(DJIController::crc8(buf)));

    buf.append(static_cast<char>(senderID));
    buf.append(static_cast<char>(receiverID));

    uint16_t idBE = qToBigEndian(msgId);
    buf.append(reinterpret_cast<const char *>(&idBE), 2);

    buf.append(static_cast<char>(flags));
    buf.append(static_cast<char>(cmdSet));
    buf.append(static_cast<char>(cmdID));

    buf.append(payload);

    uint16_t fullCrc = DJIController::crc16(buf);
    uint16_t fullCrcLE = qToLittleEndian(fullCrc);
    buf.append(reinterpret_cast<const char *>(&fullCrcLE), 2);

    return buf;
}

DJIController::DJIMessage DJIController::DJIMessage::parse(const QByteArray &data, bool *ok, bool *needMore)
{
    if (ok) *ok = false;
    if (needMore) *needMore = false;

    if (data.size() < 3) {
        if (needMore) *needMore = true;
        return {};
    }

    if (static_cast<uint8_t>(data[0]) != 0x55)
        return {};

    uint16_t length = (static_cast<uint8_t>(data[1])) |
                      ((static_cast<uint8_t>(data[2]) & 0x03) << 8);

    if (length > data.size()) {
        if (needMore) *needMore = true;
        return {};
    }

    if (data.size() < 13) {
        if (needMore) *needMore = true;
        return {};
    }

    uint8_t version = static_cast<uint8_t>(data[2]) >> 2;
    if (version != 0x01)
        return {};

    uint8_t headerCRC = static_cast<uint8_t>(data[3]);
    QByteArray header = data.left(3);
    if (DJIController::crc8(header) != headerCRC)
        return {};

    QByteArray msgWithoutCRC = data.left(length - 2);
    QByteArray providedCRCBytes = data.mid(length - 2, 2);
    uint16_t providedCRC = qFromLittleEndian<uint16_t>(
        reinterpret_cast<const uchar *>(providedCRCBytes.data()));

    if (DJIController::crc16(msgWithoutCRC) != providedCRC)
        return {};

    DJIMessage msg;
    msg.senderID = static_cast<uint8_t>(data[4]);
    msg.receiverID = static_cast<uint8_t>(data[5]);
    msg.msgId = qFromBigEndian<uint16_t>(reinterpret_cast<const uchar *>(data.data() + 6));
    msg.flags = static_cast<uint8_t>(data[8]);
    msg.cmdSet = static_cast<uint8_t>(data[9]);
    msg.cmdID = static_cast<uint8_t>(data[10]);
    msg.payload = data.mid(11, length - 13);

    if (ok) *ok = true;
    return msg;
}

// ---------------------------------------------------------------------------
// Constructor / Destructor
// ---------------------------------------------------------------------------

DJIController::DJIController(QObject *parent)
    : QObject(parent)
{
}

DJIController::~DJIController()
{
    if (m_bleController) {
        m_bleController->disconnectFromDevice();
        delete m_bleController;
        m_bleController = nullptr;
    }
    delete m_discoveryAgent;
}

// ---------------------------------------------------------------------------
// Property accessors
// ---------------------------------------------------------------------------

QVariantList DJIController::devicesList() const { return m_devicesList; }

QString DJIController::currentDevice() const { return m_currentDevice; }

void DJIController::setCurrentDevice(const QString &device)
{
    if (m_currentDevice != device) {
        m_currentDevice = device;
        emit currentDeviceChanged();
    }
}

bool DJIController::isPaired() const { return m_isPaired; }
bool DJIController::isConnected() const { return m_isConnected; }
bool DJIController::isStreaming() const { return m_isStreaming; }
QString DJIController::wifiSSID() const { return m_wifiSSID; }
QString DJIController::wifiPSK() const { return m_wifiPSK; }
QString DJIController::logText() const { return m_logText; }

void DJIController::appendLog(const QString &message)
{
    QString timestamp = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));
    m_logText += QStringLiteral("[%1] %2\n").arg(timestamp, message);
    qDebug() << "[DJI]" << message;
    emit logTextChanged();
}

void DJIController::clearLog()
{
    m_logText.clear();
    emit logTextChanged();
}

// ---------------------------------------------------------------------------
// BLE Discovery
// ---------------------------------------------------------------------------

void DJIController::startDiscovery()
{
    appendLog(QStringLiteral("Starting BLE device discovery..."));
    m_devicesList.clear();
    m_discoveredDevices.clear();
    emit devicesListChanged();

    if (!m_discoveryAgent) {
        m_discoveryAgent = new QBluetoothDeviceDiscoveryAgent(this);
        connect(m_discoveryAgent, &QBluetoothDeviceDiscoveryAgent::deviceDiscovered,
                this, &DJIController::onDeviceDiscovered);
        connect(m_discoveryAgent, &QBluetoothDeviceDiscoveryAgent::deviceUpdated,
                this, [this](const QBluetoothDeviceInfo &info, QBluetoothDeviceInfo::Fields) {
                    onDeviceDiscovered(info);
                });
        connect(m_discoveryAgent, &QBluetoothDeviceDiscoveryAgent::finished,
                this, &DJIController::onDiscoveryFinished);
        connect(m_discoveryAgent, &QBluetoothDeviceDiscoveryAgent::errorOccurred,
                this, &DJIController::onDiscoveryError);
    }

    if (m_discoveryAgent->isActive())
        m_discoveryAgent->stop();

    m_discoveryAgent->start(QBluetoothDeviceDiscoveryAgent::LowEnergyMethod);
}

void DJIController::stopDiscovery()
{
    if (m_discoveryAgent && m_discoveryAgent->isActive()) {
        m_discoveryAgent->stop();
        appendLog(QStringLiteral("BLE discovery stopped"));
    }
}

void DJIController::onDeviceDiscovered(const QBluetoothDeviceInfo &device)
{
    // Skip non-BLE devices
    if (!(device.coreConfigurations() & QBluetoothDeviceInfo::LowEnergyCoreConfiguration))
        return;

    // Check if already in list
    for (const auto &d : std::as_const(m_discoveredDevices)) {
        if (d.address() == device.address())
            return;
    }

    // Try to identify via DJI manufacturer data (key 0x08AA)
    auto manufacturerData = device.manufacturerData();
    DJIDeviceType devType = DJIDeviceType::Undefined;

    if (manufacturerData.contains(DJIManufacturerDataKey)) {
        devType = identifyDeviceType(manufacturerData.value(DJIManufacturerDataKey));
    }

    // Also accept devices whose name contains "DJI" or "Osmo"
    if (devType == DJIDeviceType::Undefined) {
        const QString name = device.name();
        if (name.contains(QStringLiteral("DJI"), Qt::CaseInsensitive) ||
            name.contains(QStringLiteral("Osmo"), Qt::CaseInsensitive) ||
            name.contains(QStringLiteral("Action"), Qt::CaseInsensitive)) {
            devType = DJIDeviceType::Unknown;
        }
    }

    if (devType == DJIDeviceType::Undefined)
        return;

    m_discoveredDevices.append(device);

    QVariantMap entry;
    entry[QStringLiteral("address")] = device.address().toString();
    entry[QStringLiteral("name")] = device.name().isEmpty()
        ? QStringLiteral("DJI Device")
        : device.name();
    entry[QStringLiteral("deviceType")] = static_cast<int>(devType);
    m_devicesList.append(entry);
    emit devicesListChanged();

    appendLog(QStringLiteral("Found DJI device: %1 (%2)")
              .arg(entry[QStringLiteral("name")].toString(),
                   entry[QStringLiteral("address")].toString()));
}

void DJIController::onDiscoveryFinished()
{
    appendLog(QStringLiteral("BLE discovery finished. Found %1 DJI device(s)")
              .arg(m_discoveredDevices.size()));
}

void DJIController::onDiscoveryError(QBluetoothDeviceDiscoveryAgent::Error error)
{
    QString errMsg = m_discoveryAgent ? m_discoveryAgent->errorString()
                                      : QStringLiteral("Unknown error");
    appendLog(QStringLiteral("BLE discovery error (%1): %2").arg(error).arg(errMsg));
    emit errorOccurred(errMsg);
}

// ---------------------------------------------------------------------------
// BLE Connection
// ---------------------------------------------------------------------------

void DJIController::connectToDevice(const QString &address)
{
    appendLog(QStringLiteral("Connecting to device: %1").arg(address));

    // Find the device info
    QBluetoothDeviceInfo targetInfo;
    bool found = false;
    for (const auto &d : std::as_const(m_discoveredDevices)) {
        if (d.address().toString() == address) {
            targetInfo = d;
            found = true;
            break;
        }
    }

    if (!found) {
        appendLog(QStringLiteral("Device %1 not found in discovered list").arg(address));
        emit errorOccurred(QStringLiteral("Device not found: %1").arg(address));
        return;
    }

    // Identify device type for protocol purposes
    auto mfData = targetInfo.manufacturerData();
    if (mfData.contains(DJIManufacturerDataKey))
        m_connectedDeviceType = identifyDeviceType(mfData.value(DJIManufacturerDataKey));
    else
        m_connectedDeviceType = DJIDeviceType::Unknown;

    // Clean up previous connection
    if (m_bleController) {
        m_bleController->disconnectFromDevice();
        m_bleController->deleteLater();
        m_bleController = nullptr;
    }
    m_djiService = nullptr;
    m_bleInitialized = false;
    m_receiveBuffer.clear();
    m_charReceiver = QLowEnergyCharacteristic();
    m_charSender = QLowEnergyCharacteristic();
    m_charPairingRequestor = QLowEnergyCharacteristic();

    m_bleController = QLowEnergyController::createCentral(targetInfo, this);
    connect(m_bleController, &QLowEnergyController::connected,
            this, &DJIController::onBLEConnected);
    connect(m_bleController, &QLowEnergyController::disconnected,
            this, &DJIController::onBLEDisconnected);
    connect(m_bleController, &QLowEnergyController::errorOccurred,
            this, &DJIController::onBLEError);
    connect(m_bleController, &QLowEnergyController::serviceDiscovered,
            this, &DJIController::onServiceDiscovered);
    connect(m_bleController, &QLowEnergyController::discoveryFinished,
            this, &DJIController::onServiceDiscoveryFinished);

    m_flowState = FlowState::Connecting;
    setCurrentDevice(address);
    m_bleController->connectToDevice();
}

void DJIController::disconnectDevice()
{
    appendLog(QStringLiteral("Disconnecting device"));
    m_flowState = FlowState::Idle;

    if (m_bleController) {
        m_bleController->disconnectFromDevice();
        m_bleController->deleteLater();
        m_bleController = nullptr;
    }

    m_djiService = nullptr;
    m_bleInitialized = false;
    m_receiveBuffer.clear();
    m_charReceiver = QLowEnergyCharacteristic();
    m_charSender = QLowEnergyCharacteristic();
    m_charPairingRequestor = QLowEnergyCharacteristic();

    if (m_isConnected) {
        m_isConnected = false;
        emit isConnectedChanged();
    }
    if (m_isPaired) {
        m_isPaired = false;
        emit isPairedChanged();
    }
    if (m_isStreaming) {
        m_isStreaming = false;
        emit isStreamingChanged();
    }
}

void DJIController::onBLEConnected()
{
    appendLog(QStringLiteral("BLE connected. Discovering services..."));

    m_isConnected = true;
    emit isConnectedChanged();
    m_flowState = FlowState::WaitingInit;

    m_bleController->discoverServices();
}

void DJIController::onBLEDisconnected()
{
    appendLog(QStringLiteral("BLE disconnected"));
    m_bleInitialized = false;
    m_djiService = nullptr;

    bool wasConnected = m_isConnected;
    bool wasPaired = m_isPaired;
    bool wasStreaming = m_isStreaming;

    m_isConnected = false;
    m_isPaired = false;
    m_isStreaming = false;
    m_flowState = FlowState::Idle;

    if (wasConnected) emit isConnectedChanged();
    if (wasPaired)    emit isPairedChanged();
    if (wasStreaming)  emit isStreamingChanged();
}

void DJIController::onBLEError(QLowEnergyController::Error error)
{
    QString errMsg = m_bleController ? m_bleController->errorString()
                                      : QStringLiteral("Unknown");
    appendLog(QStringLiteral("BLE error (%1): %2").arg(error).arg(errMsg));
    emit errorOccurred(errMsg);
}

void DJIController::onServiceDiscovered(const QBluetoothUuid &serviceUuid)
{
    appendLog(QStringLiteral("Service discovered: %1").arg(serviceUuid.toString()));
}

void DJIController::onServiceDiscoveryFinished()
{
    appendLog(QStringLiteral("Service discovery finished. Searching for DJI characteristics..."));

    if (!m_bleController)
        return;

    auto serviceUuids = m_bleController->services();
    for (const auto &uuid : serviceUuids) {
        QLowEnergyService *service = m_bleController->createServiceObject(uuid, this);
        if (!service)
            continue;

        connect(service, &QLowEnergyService::stateChanged,
                this, &DJIController::onServiceStateChanged);
        connect(service, &QLowEnergyService::characteristicChanged,
                this, &DJIController::onCharacteristicChanged);

        service->discoverDetails();
    }
}

void DJIController::onServiceStateChanged(QLowEnergyService::ServiceState newState)
{
    if (newState != QLowEnergyService::RemoteServiceDiscovered)
        return;

    auto *service = qobject_cast<QLowEnergyService *>(sender());
    if (!service)
        return;

    const auto chars = service->characteristics();
    appendLog(QStringLiteral("Service %1: %2 characteristics")
              .arg(service->serviceUuid().toString())
              .arg(chars.size()));

    for (const QLowEnergyCharacteristic &c : chars) {
        // Log characteristic details
        QString props;
        if (c.properties() & QLowEnergyCharacteristic::Read)           props += QStringLiteral("R ");
        if (c.properties() & QLowEnergyCharacteristic::Write)          props += QStringLiteral("W ");
        if (c.properties() & QLowEnergyCharacteristic::WriteNoResponse) props += QStringLiteral("WnR ");
        if (c.properties() & QLowEnergyCharacteristic::Notify)         props += QStringLiteral("N ");
        if (c.properties() & QLowEnergyCharacteristic::Indicate)       props += QStringLiteral("I ");
        appendLog(QStringLiteral("  Char %1 [%2]").arg(c.uuid().toString(), props.trimmed()));

        // Match by 16-bit UUID handle (DJI convention)
        bool isReceiver = (c.uuid() == QBluetoothUuid(CharHandleReceiver));
        bool isSender   = (c.uuid() == QBluetoothUuid(CharHandleSender));
        bool isPairing  = (c.uuid() == QBluetoothUuid(CharHandlePairingRequestor));

        if (isReceiver) {
            m_charReceiver = c;
            // Enable notifications on the receiver characteristic
            QLowEnergyDescriptor desc =
                c.descriptor(QBluetoothUuid::DescriptorType::ClientCharacteristicConfiguration);
            if (desc.isValid()) {
                service->writeDescriptor(desc, QByteArray::fromHex("0100"));
                appendLog(QStringLiteral("  -> Enabled notifications on receiver (0x%1)")
                          .arg(CharHandleReceiver, 4, 16, QChar('0')));
            }
        } else if (isSender) {
            m_charSender = c;
            appendLog(QStringLiteral("  -> Found sender characteristic (0x%1)")
                      .arg(CharHandleSender, 4, 16, QChar('0')));
        } else if (isPairing) {
            m_charPairingRequestor = c;
            appendLog(QStringLiteral("  -> Found pairing requestor characteristic (0x%1)")
                      .arg(CharHandlePairingRequestor, 4, 16, QChar('0')));
        }
    }

    // Check if all three DJI characteristics are found
    if (m_charReceiver.isValid() && m_charSender.isValid() && m_charPairingRequestor.isValid()) {
        if (!m_bleInitialized) {
            m_bleInitialized = true;
            m_djiService = service;
            appendLog(QStringLiteral("Device initialized. All DJI characteristics found."));

            // If we were in a streaming flow, proceed to pairing
            if (m_flowState == FlowState::WaitingInit) {
                m_flowState = FlowState::Pairing;
                doPairing();
            }
        }
    }
}

void DJIController::onCharacteristicChanged(const QLowEnergyCharacteristic &c,
                                             const QByteArray &value)
{
    if (!m_charReceiver.isValid() || c.uuid() != m_charReceiver.uuid())
        return;

    // Accumulate data and try to parse complete messages
    m_receiveBuffer.append(value);

    while (!m_receiveBuffer.isEmpty()) {
        bool ok = false;
        bool needMore = false;
        DJIMessage msg = DJIMessage::parse(m_receiveBuffer, &ok, &needMore);

        if (needMore)
            return;

        if (!ok) {
            appendLog(QStringLiteral("Failed to parse BLE message, clearing buffer (%1 bytes)")
                      .arg(m_receiveBuffer.size()));
            m_receiveBuffer.clear();
            return;
        }

        // Remove consumed bytes
        uint16_t length = (static_cast<uint8_t>(m_receiveBuffer[1])) |
                          ((static_cast<uint8_t>(m_receiveBuffer[2]) & 0x03) << 8);
        m_receiveBuffer.remove(0, length);

        // Send ACK if required
        if (msg.flags & FlagAckRequired)
            sendACK(msg);

        appendLog(QStringLiteral("Rx: sender=0x%1 recv=0x%2 id=0x%3 flags=0x%4 set=0x%5 cmd=0x%6")
                  .arg(msg.senderID, 2, 16, QChar('0'))
                  .arg(msg.receiverID, 2, 16, QChar('0'))
                  .arg(msg.msgId, 4, 16, QChar('0'))
                  .arg(msg.flags, 2, 16, QChar('0'))
                  .arg(msg.cmdSet, 2, 16, QChar('0'))
                  .arg(msg.cmdID, 2, 16, QChar('0')));

        handleIncomingMessage(msg);
    }
}

// ---------------------------------------------------------------------------
// Sending messages over BLE
// ---------------------------------------------------------------------------

void DJIController::sendMessage(const DJIMessage &msg, bool noResponse)
{
    if (!m_bleInitialized || !m_djiService || !m_charSender.isValid()) {
        appendLog(QStringLiteral("Cannot send: device not initialized"));
        emit errorOccurred(QStringLiteral("Device not initialized"));
        return;
    }

    QByteArray data = msg.serialize();
    auto mode = noResponse ? QLowEnergyService::WriteWithoutResponse
                           : QLowEnergyService::WriteWithResponse;
    m_djiService->writeCharacteristic(m_charSender, data, mode);
}

void DJIController::sendACK(const DJIMessage &msg)
{
    DJIMessage ack;
    ack.senderID = msg.receiverID;
    ack.receiverID = msg.senderID;
    ack.msgId = msg.msgId;
    ack.flags = FlagResponse;
    ack.cmdSet = msg.cmdSet;
    ack.cmdID = msg.cmdID;
    ack.payload = QByteArray::fromHex("00");
    sendMessage(ack, true);
}

void DJIController::sendRawPairing(const QByteArray &data)
{
    if (!m_bleInitialized || !m_djiService || !m_charPairingRequestor.isValid()) {
        appendLog(QStringLiteral("Cannot send pairing: device not initialized"));
        emit errorOccurred(QStringLiteral("Device not initialized for pairing"));
        return;
    }

    m_djiService->writeCharacteristic(m_charPairingRequestor, data,
                                       QLowEnergyService::WriteWithoutResponse);
}

// ---------------------------------------------------------------------------
// DJI Protocol Actions
// ---------------------------------------------------------------------------

void DJIController::doPairing()
{
    appendLog(QStringLiteral("Starting pairing process..."));

    // Step 1: Send raw pairing start request (write 0x0100 to char 0x002E)
    sendRawPairing(QByteArray::fromHex("0100"));

    // Step 2: Send SetPairingPIN message with default PIN "5160"
    static const QString defaultPIN = QStringLiteral("5160");

    QByteArray payload;
    payload.append(packString(QStringLiteral("001749319286102")));
    payload.append(packString(defaultPIN));

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x07; // WiFi Ground Station
    msg.msgId = static_cast<uint16_t>(MsgID::SetPairingPIN);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::WiFi);
    msg.cmdID = static_cast<uint8_t>(CmdID::SetPairingPIN);
    msg.payload = payload;

    sendMessage(msg, true);

    m_flowState = FlowState::WaitingPairResult;
}

void DJIController::doPrepareToLiveStream()
{
    appendLog(QStringLiteral("Preparing to live stream..."));

    m_prepareStage = 1;

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x08; // Video Transmission
    msg.msgId = static_cast<uint16_t>(MsgID::PrepareToLiveStreamStage1);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::Camera);
    msg.cmdID = static_cast<uint8_t>(CmdID::PrepareToLiveStream);
    msg.payload.append(static_cast<char>(0x1A));

    sendMessage(msg, true);

    m_flowState = FlowState::WaitingPrepareResult;
}

void DJIController::doConnectWiFi()
{
    appendLog(QStringLiteral("Connecting camera to WiFi: SSID=%1").arg(m_wifiSSID));

    QByteArray payload;
    payload.append(packString(m_wifiSSID));
    payload.append(packString(m_wifiPSK));

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x07; // WiFi Ground Station
    msg.msgId = static_cast<uint16_t>(MsgID::ConnectToWiFi);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::WiFi);
    msg.cmdID = static_cast<uint8_t>(CmdID::ConnectToWiFi);
    msg.payload = payload;

    sendMessage(msg, true);

    m_flowState = FlowState::WaitingWiFiResult;
}

void DJIController::doConfigureStreaming()
{
    appendLog(QStringLiteral("Configuring live stream: %1x%2 @ %3fps, %4 kbps")
              .arg(m_pendingWidth).arg(m_pendingHeight)
              .arg(m_pendingFps).arg(m_pendingBitrateKbps));

    // Map resolution
    DJIResolution res = DJIResolution::Res1080p;
    if (m_pendingHeight <= 480)
        res = DJIResolution::Res480p;
    else if (m_pendingHeight <= 720)
        res = DJIResolution::Res720p;

    // Map FPS
    DJIFPS fps = DJIFPS::FPS30;
    if (m_pendingFps <= 24)
        fps = DJIFPS::FPS24;
    else if (m_pendingFps <= 25)
        fps = DJIFPS::FPS25;

    QByteArray payload;
    payload.append(static_cast<char>(0x00));
    payload.append(static_cast<char>(deviceTypeToByte(m_connectedDeviceType)));
    payload.append(static_cast<char>(0x00));
    payload.append(static_cast<char>(static_cast<uint8_t>(res)));

    uint16_t brLE = qToLittleEndian<uint16_t>(static_cast<uint16_t>(m_pendingBitrateKbps));
    payload.append(reinterpret_cast<const char *>(&brLE), 2);

    payload.append(static_cast<char>(0x02));
    payload.append(static_cast<char>(0x00));
    payload.append(static_cast<char>(static_cast<uint8_t>(fps)));
    payload.append(static_cast<char>(0x00));
    payload.append(static_cast<char>(0x00));
    payload.append(static_cast<char>(0x00));
    payload.append(packURL(m_pendingRtmpUrl));

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x08; // Video Transmission
    msg.msgId = static_cast<uint16_t>(MsgID::ConfigureStreaming);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::Config);
    msg.cmdID = static_cast<uint8_t>(CmdID::ConfigureStreaming);
    msg.payload = payload;

    sendMessage(msg, true);

    m_flowState = FlowState::WaitingConfigResult;
}

void DJIController::doStartStreaming()
{
    appendLog(QStringLiteral("Starting live stream..."));

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x08; // Video Transmission
    msg.msgId = static_cast<uint16_t>(MsgID::StartStreaming);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::Camera);
    msg.cmdID = static_cast<uint8_t>(CmdID::StartStopStreaming);
    msg.payload = QByteArray::fromHex("01011A000101");

    sendMessage(msg, true);

    m_flowState = FlowState::WaitingStartResult;
}

void DJIController::doStopStreaming()
{
    appendLog(QStringLiteral("Stopping live stream..."));

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x08; // Video Transmission
    msg.msgId = static_cast<uint16_t>(MsgID::StopStreaming);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::Camera);
    msg.cmdID = static_cast<uint8_t>(CmdID::StartStopStreaming);
    msg.payload = QByteArray::fromHex("01011A000102");

    sendMessage(msg, true);

    m_flowState = FlowState::Stopping;
}

void DJIController::doRequestCameraAPInfo()
{
    appendLog(QStringLiteral("Requesting camera AP info (SSID + PSK)..."));

    m_cameraSSID.clear();
    m_cameraPSK.clear();

    DJIMessage msg;
    msg.senderID = 0x02;   // App
    msg.receiverID = 0x07; // WiFi Ground Station
    msg.msgId = static_cast<uint16_t>(MsgID::CameraAPInfo);
    msg.flags = FlagRequest;
    msg.cmdSet = static_cast<uint8_t>(CmdSet::WiFi);
    msg.cmdID = static_cast<uint8_t>(CmdID::CameraAPInfo);
    msg.payload = QByteArray::fromHex("20");

    sendMessage(msg, true);
    m_flowState = FlowState::RequestingWiFiInfo;
}

// ---------------------------------------------------------------------------
// Incoming message handling and state machine
// ---------------------------------------------------------------------------

void DJIController::handleIncomingMessage(const DJIMessage &msg)
{
    // Pairing status response (already paired)
    // MessageTypePairingStatus: response(WiFi, SetPairingPIN, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::WiFi)
        && msg.cmdID == static_cast<uint8_t>(CmdID::SetPairingPIN)) {

        if (msg.payload.size() >= 2 && static_cast<uint8_t>(msg.payload[1]) == 0x01) {
            appendLog(QStringLiteral("Device is already paired"));
            m_isPaired = true;
            emit isPairedChanged();

            // Continue flow: prepare to live stream
            if (m_flowState == FlowState::WaitingPairResult) {
                m_flowState = FlowState::Preparing;
                doPrepareToLiveStream();
            }
        }
        return;
    }

    // Pairing PIN approved
    // MessageTypePairingPINApproved: request(WiFi, PairingPINApproved)
    if (msg.flags == FlagRequest
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::WiFi)
        && msg.cmdID == static_cast<uint8_t>(CmdID::PairingPINApproved)) {

        appendLog(QStringLiteral("PIN approved. Finalizing pairing..."));

        // Send pairing stage 1 (PairingStage1 response)
        {
            DJIMessage stage1;
            stage1.senderID = 0x02;
            stage1.receiverID = 0x07;
            stage1.msgId = static_cast<uint16_t>(MsgID::PairingStage1);
            stage1.flags = 0xC0; // response
            stage1.cmdSet = static_cast<uint8_t>(CmdSet::WiFi);
            stage1.cmdID = static_cast<uint8_t>(CmdID::PairingPINApproved);
            stage1.payload = QByteArray::fromHex("00");
            sendMessage(stage1, true);
        }

        // Send pairing stage 2
        {
            DJIMessage stage2;
            stage2.senderID = 0x02;
            stage2.receiverID = 0x88; // Pairer
            stage2.msgId = static_cast<uint16_t>(MsgID::PairingStage2);
            stage2.flags = FlagRequest;
            stage2.cmdSet = static_cast<uint8_t>(CmdSet::Core);
            stage2.cmdID = static_cast<uint8_t>(CmdID::PairingStage2);
            stage2.payload = QByteArray::fromHex("3131000000");
            sendMessage(stage2, true);
        }

        m_isPaired = true;
        emit isPairedChanged();

        // Continue flow
        if (m_flowState == FlowState::WaitingPairResult) {
            m_flowState = FlowState::Preparing;
            doPrepareToLiveStream();
        }
        return;
    }

    // Prepare to live stream result
    // MessageTypePrepareToLiveStreamResult: response(Camera, PrepareToLiveStream, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::Camera)
        && msg.cmdID == static_cast<uint8_t>(CmdID::PrepareToLiveStream)) {

        if (m_prepareStage == 1) {
            appendLog(QStringLiteral("Prepare stage 1 complete. Sending stage 2..."));
            m_prepareStage = 2;

            // Send stage 2: StartStopStreaming with prepare payload
            DJIMessage stage2;
            stage2.senderID = 0x02;
            stage2.receiverID = 0x08;
            stage2.msgId = static_cast<uint16_t>(MsgID::StartStreaming);
            stage2.flags = FlagRequest;
            stage2.cmdSet = static_cast<uint8_t>(CmdSet::Camera);
            stage2.cmdID = static_cast<uint8_t>(CmdID::StartStopStreaming);
            stage2.payload = QByteArray::fromHex("00011C00");
            sendMessage(stage2, false);
        }
        return;
    }

    // StartStopStreaming result
    // MessageTypeStartStopStreamingResult: response(Camera, StartStopStreaming)
    if (msg.flags == FlagResponse
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::Camera)
        && msg.cmdID == static_cast<uint8_t>(CmdID::StartStopStreaming)) {

        if (m_prepareStage == 2) {
            // Preparation complete
            m_prepareStage = 0;
            appendLog(QStringLiteral("Prepare to live stream complete"));

            if (m_flowState == FlowState::WaitingPrepareResult) {
                // Next: connect camera to WiFi
                m_flowState = FlowState::ConnectingWiFi;
                doConnectWiFi();
            }
        } else if (m_flowState == FlowState::WaitingStartResult) {
            appendLog(QStringLiteral("Live stream started successfully"));
            m_isStreaming = true;
            emit isStreamingChanged();
            m_flowState = FlowState::Streaming;
        } else if (m_flowState == FlowState::Stopping) {
            appendLog(QStringLiteral("Live stream stopped"));
            m_isStreaming = false;
            emit isStreamingChanged();
            m_flowState = FlowState::Idle;
        }
        return;
    }

    // WiFi connect result
    // MessageTypeConnectToWiFiResult: response(WiFi, ConnectToWiFi, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::WiFi)
        && msg.cmdID == static_cast<uint8_t>(CmdID::ConnectToWiFi)) {

        if (msg.payload.size() >= 2 && msg.payload[0] == 0x00 && msg.payload[1] == 0x00) {
            appendLog(QStringLiteral("Camera connected to WiFi successfully"));
            if (m_flowState == FlowState::WaitingWiFiResult) {
                m_flowState = FlowState::Configuring;
                doConfigureStreaming();
            }
        } else {
            appendLog(QStringLiteral("WiFi connection failed. Payload: %1")
                      .arg(QString(msg.payload.toHex())));
            emit errorOccurred(QStringLiteral("WiFi connection failed"));
            m_flowState = FlowState::Idle;
        }
        return;
    }

    // Configure streaming result
    // MessageTypeConfigureStreamingResult: response(Config, ConfigureStreaming, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::Config)
        && msg.cmdID == static_cast<uint8_t>(CmdID::ConfigureStreaming)) {

        appendLog(QStringLiteral("Streaming configured. Starting stream..."));
        if (m_flowState == FlowState::WaitingConfigResult) {
            m_flowState = FlowState::Starting;
            doStartStreaming();
        }
        return;
    }

    // Camera AP Info SSID response
    // MessageTypeCameraAPInfoResultSSID: response(WiFi, CameraAPInfo, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::WiFi)
        && msg.cmdID == static_cast<uint8_t>(CmdID::CameraAPInfo)) {

        m_cameraSSID = unpackStringU16BE(msg.payload);
        appendLog(QStringLiteral("Camera AP SSID: %1").arg(m_cameraSSID));

        // Also request PSK
        DJIMessage pskMsg;
        pskMsg.senderID = 0x02;
        pskMsg.receiverID = 0x07;
        pskMsg.msgId = static_cast<uint16_t>(MsgID::CameraAPInfo);
        pskMsg.flags = FlagRequest;
        pskMsg.cmdSet = static_cast<uint8_t>(CmdSet::WiFi);
        pskMsg.cmdID = static_cast<uint8_t>(CmdID::CameraAPPSK);
        pskMsg.payload = QByteArray::fromHex("20");
        sendMessage(pskMsg, true);

        if (!m_cameraSSID.isEmpty() && !m_cameraPSK.isEmpty()) {
            m_wifiSSID = m_cameraSSID;
            m_wifiPSK = m_cameraPSK;
            emit wifiInfoChanged();
            m_flowState = FlowState::Idle;
        }
        return;
    }

    // Camera AP Info PSK response
    // MessageTypeCameraAPInfoResultPSK: response(WiFi, CameraAPPSK, 0xC0)
    if (msg.flags == 0xC0
        && msg.cmdSet == static_cast<uint8_t>(CmdSet::WiFi)
        && msg.cmdID == static_cast<uint8_t>(CmdID::CameraAPPSK)) {

        m_cameraPSK = unpackStringU16BE(msg.payload);
        appendLog(QStringLiteral("Camera AP PSK: %1").arg(m_cameraPSK));

        if (!m_cameraSSID.isEmpty() && !m_cameraPSK.isEmpty()) {
            m_wifiSSID = m_cameraSSID;
            m_wifiPSK = m_cameraPSK;
            emit wifiInfoChanged();
            m_flowState = FlowState::Idle;
        }
        return;
    }
}

// ---------------------------------------------------------------------------
// Public Q_INVOKABLE methods
// ---------------------------------------------------------------------------

void DJIController::startStreaming(const QString &rtmpUrl, int width, int height,
                                    int fps, int bitrateKbps)
{
    appendLog(QStringLiteral("Streaming requested: %1 (%2x%3 @ %4fps, %5 kbps)")
              .arg(rtmpUrl).arg(width).arg(height).arg(fps).arg(bitrateKbps));

    if (m_wifiSSID.isEmpty() || m_wifiPSK.isEmpty()) {
        appendLog(QStringLiteral("Warning: WiFi SSID/PSK not set. "
                                  "Camera may fail to connect to WiFi for RTMP streaming."));
    }

    m_pendingRtmpUrl = rtmpUrl;
    m_pendingWidth = width;
    m_pendingHeight = height;
    m_pendingFps = fps;
    m_pendingBitrateKbps = bitrateKbps;

    if (!m_bleInitialized) {
        appendLog(QStringLiteral("Device not initialized. Connect first."));
        emit errorOccurred(QStringLiteral("Not connected to a DJI device"));
        return;
    }

    // If already paired, skip pairing and go directly to prepare
    if (m_isPaired) {
        m_flowState = FlowState::Preparing;
        doPrepareToLiveStream();
    } else {
        m_flowState = FlowState::Pairing;
        doPairing();
    }
}

void DJIController::stopStreaming()
{
    if (!m_bleInitialized) {
        appendLog(QStringLiteral("Device not initialized"));
        m_isStreaming = false;
        emit isStreamingChanged();
        return;
    }

    doStopStreaming();
}

void DJIController::requestWiFiInfo()
{
    if (!m_bleInitialized) {
        appendLog(QStringLiteral("Device not initialized. Connect first."));
        emit errorOccurred(QStringLiteral("Not connected to a DJI device"));
        return;
    }

    if (!m_isPaired) {
        // Need to pair first, then request info
        appendLog(QStringLiteral("Not paired yet. Pairing first, then requesting WiFi info..."));
        m_flowState = FlowState::Pairing;
        doPairing();
        // The WiFi info request will need to be called again after pairing
        // For now, queue it via a timer
        QTimer::singleShot(3000, this, [this]() {
            if (m_isPaired && m_bleInitialized)
                doRequestCameraAPInfo();
        });
        return;
    }

    doRequestCameraAPInfo();
}
