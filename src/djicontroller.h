#ifndef DJICONTROLLER_H
#define DJICONTROLLER_H

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantList>
#include <QTimer>
#include <QBluetoothDeviceDiscoveryAgent>
#include <QBluetoothDeviceInfo>
#include <QLowEnergyController>
#include <QLowEnergyService>
#include <QLowEnergyCharacteristic>
#include <QLowEnergyDescriptor>

class DJIController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList devicesList READ devicesList NOTIFY devicesListChanged)
    Q_PROPERTY(QString currentDevice READ currentDevice WRITE setCurrentDevice NOTIFY currentDeviceChanged)
    Q_PROPERTY(bool isPaired READ isPaired NOTIFY isPairedChanged)
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY isConnectedChanged)
    Q_PROPERTY(bool isStreaming READ isStreaming NOTIFY isStreamingChanged)
    Q_PROPERTY(QString wifiSSID READ wifiSSID NOTIFY wifiInfoChanged)
    Q_PROPERTY(QString wifiPSK READ wifiPSK NOTIFY wifiInfoChanged)
    Q_PROPERTY(QString logText READ logText NOTIFY logTextChanged)

public:
    explicit DJIController(QObject *parent = nullptr);
    ~DJIController() override;

    QVariantList devicesList() const;
    QString currentDevice() const;
    void setCurrentDevice(const QString &device);
    bool isPaired() const;
    bool isConnected() const;
    bool isStreaming() const;
    QString wifiSSID() const;
    QString wifiPSK() const;
    QString logText() const;

    Q_INVOKABLE void startDiscovery();
    Q_INVOKABLE void stopDiscovery();
    Q_INVOKABLE void connectToDevice(const QString &address);
    Q_INVOKABLE void disconnectDevice();
    Q_INVOKABLE void startStreaming(const QString &rtmpUrl, int width, int height,
                                     int fps, int bitrateKbps);
    Q_INVOKABLE void stopStreaming();
    Q_INVOKABLE void requestWiFiInfo();
    Q_INVOKABLE void clearLog();

signals:
    void devicesListChanged();
    void currentDeviceChanged();
    void isPairedChanged();
    void isConnectedChanged();
    void isStreamingChanged();
    void wifiInfoChanged();
    void logTextChanged();
    void errorOccurred(const QString &error);

private:
    // --- DJI BLE protocol constants ---

    // BLE characteristic handles used by DJI devices
    static constexpr uint16_t CharHandleReceiver = 0x002D;
    static constexpr uint16_t CharHandlePairingRequestor = 0x002E;
    static constexpr uint16_t CharHandleSender = 0x0030;

    // DJI manufacturer data key
    static constexpr uint16_t DJIManufacturerDataKey = 0x08AA;

    // DJI device types (identified from manufacturer data byte at offset 2)
    enum class DJIDeviceType : uint8_t {
        Unknown = 0,
        OsmoPocket3 = 0x2A,
        OsmoAction4 = 0x2E,
        OsmoAction5Pro = 0x2F,
        Undefined = 0xFF
    };

    // Command sets
    enum class CmdSet : uint8_t {
        Core = 0x00,
        Camera = 0x02,
        WiFi = 0x07,
        Config = 0x08,
    };

    // Command IDs
    enum class CmdID : uint8_t {
        PairingStage2 = 0x32,
        SetPairingPIN = 0x45,
        PairingPINApproved = 0x46,
        ConnectToWiFi = 0x47,
        CameraAPInfo = 0x07,
        CameraAPPSK = 0x0E,
        PrepareToLiveStream = 0xE1,
        StartStopStreaming = 0x8E,
        ConfigureStreaming = 0x78,
        FCCSupport = 0xDE,
        StartScanningWiFi = 0xAB,
    };

    // Message IDs (16-bit, big-endian in wire format)
    enum class MsgID : uint16_t {
        SetPairingPIN = 0x72AA,
        PairingPINApproved = 0x72AA,
        PairingStage1 = 0x0400,
        PairingStage2 = 0x74AA,
        ConnectToWiFi = 0x98BB,
        ConfigureStreaming = 0xB3BB,
        StartStreaming = 0xB4BB,
        StopStreaming = 0xB5BB,
        CameraAPInfo = 0x76AA,
        PrepareToLiveStreamStage1 = 0xFEAB,
        StartScanningWiFi = 0x8EBB,
    };

    // Resolution values for streaming configuration
    enum class DJIResolution : uint8_t {
        Res480p = 0x47,
        Res720p = 0x04,
        Res1080p = 0x0A,
    };

    // FPS values for streaming configuration
    enum class DJIFPS : uint8_t {
        FPS24 = 0x01,
        FPS25 = 0x02,
        FPS30 = 0x03,
    };

    // Message type flags
    static constexpr uint8_t FlagRequest = 0x40;
    static constexpr uint8_t FlagResponse = 0x80;
    static constexpr uint8_t FlagAckRequired = 0x40;

    // A parsed/serializable DJI BLE message
    struct DJIMessage {
        uint8_t senderID = 0x02;   // App
        uint8_t receiverID = 0x02; // App
        uint16_t msgId = 0;
        uint8_t flags = 0;
        uint8_t cmdSet = 0;
        uint8_t cmdID = 0;
        QByteArray payload;

        QByteArray serialize() const;
        static DJIMessage parse(const QByteArray &data, bool *ok, bool *needMore);
    };

    // State machine for the streaming flow
    enum class FlowState {
        Idle,
        Connecting,
        WaitingInit,
        Pairing,
        WaitingPairResult,
        Preparing,
        WaitingPrepareResult,
        ConnectingWiFi,
        WaitingWiFiResult,
        Configuring,
        WaitingConfigResult,
        Starting,
        WaitingStartResult,
        Streaming,
        Stopping,
        RequestingWiFiInfo,
    };

    // --- Helper methods ---
    void appendLog(const QString &message);

    // CRC
    static uint8_t crc8(const QByteArray &data);
    static uint16_t crc16(const QByteArray &data);

    // Message construction helpers
    static QByteArray packString(const QString &s);
    static QByteArray packURL(const QString &s);
    static QString unpackStringU16BE(const QByteArray &data);

    // Device type identification
    static DJIDeviceType identifyDeviceType(const QByteArray &manufacturerData);
    static uint8_t deviceTypeToByte(DJIDeviceType t);

    // Send a DJI message over BLE
    void sendMessage(const DJIMessage &msg, bool noResponse = true);
    void sendACK(const DJIMessage &msg);
    void sendRawPairing(const QByteArray &data);

    // Protocol actions
    void doPairing();
    void doPrepareToLiveStream();
    void doConnectWiFi();
    void doConfigureStreaming();
    void doStartStreaming();
    void doStopStreaming();
    void doRequestCameraAPInfo();

    // Incoming message handling
    void handleIncomingMessage(const DJIMessage &msg);

    // --- BLE discovery slots ---
    void onDeviceDiscovered(const QBluetoothDeviceInfo &device);
    void onDiscoveryFinished();
    void onDiscoveryError(QBluetoothDeviceDiscoveryAgent::Error error);

    // --- BLE connection slots ---
    void onBLEConnected();
    void onBLEDisconnected();
    void onBLEError(QLowEnergyController::Error error);
    void onServiceDiscovered(const QBluetoothUuid &serviceUuid);
    void onServiceDiscoveryFinished();
    void onServiceStateChanged(QLowEnergyService::ServiceState newState);
    void onCharacteristicChanged(const QLowEnergyCharacteristic &c, const QByteArray &value);

    // --- State ---
    QVariantList m_devicesList;
    QString m_currentDevice;
    bool m_isPaired = false;
    bool m_isConnected = false;
    bool m_isStreaming = false;
    QString m_wifiSSID;
    QString m_wifiPSK;
    QString m_logText;

    // BLE objects
    QBluetoothDeviceDiscoveryAgent *m_discoveryAgent = nullptr;
    QLowEnergyController *m_bleController = nullptr;
    QLowEnergyService *m_djiService = nullptr;

    // DJI BLE characteristics
    QLowEnergyCharacteristic m_charReceiver;
    QLowEnergyCharacteristic m_charSender;
    QLowEnergyCharacteristic m_charPairingRequestor;
    bool m_bleInitialized = false;

    // Discovered devices (address -> info)
    QList<QBluetoothDeviceInfo> m_discoveredDevices;
    DJIDeviceType m_connectedDeviceType = DJIDeviceType::Undefined;

    // Receive buffer for reassembling multi-part notifications
    QByteArray m_receiveBuffer;

    // Streaming flow state machine
    FlowState m_flowState = FlowState::Idle;
    int m_prepareStage = 0;

    // Streaming parameters (saved for use during the flow)
    QString m_pendingRtmpUrl;
    int m_pendingWidth = 1920;
    int m_pendingHeight = 1080;
    int m_pendingFps = 30;
    int m_pendingBitrateKbps = 4000;

    // Camera AP info state (SSID and PSK arrive in separate messages)
    QString m_cameraSSID;
    QString m_cameraPSK;
};

#endif // DJICONTROLLER_H
