# WingOut Summary

`WingOut` is a Qt/QML-based Android and Linux application that serves as a control panel and dashboard for the `ffstream` live streaming tool.

## Key Components

### 1. UI Architecture (`Main.qml`, `Dashboard.qml`, `Cameras.qml`)
- Uses `StackLayout` to switch between `Dashboard` and `Cameras` pages.
- **Dashboard**: Real-time monitoring of stream health (latency, bitrate, quality) and chat integration.
- **Cameras**: Interface for managing built-in camera settings and discovering remote cameras.
- **SwipeLockOverlay**: A safety feature to prevent accidental touches during streaming.

### 2. FFStream Integration (`ffstream_client.h`, `ffstream_client.cpp`)
- Communicates with the `ffstream` daemon via gRPC.
- Uses `QtGrpc` for generating client stubs from `.proto` files.
- Fetches metrics like latencies, input/output quality, and bitrates.

### 3. Remote Camera Control (`remote_camera_controller.h`, `ble_remote_device.h`)
- Implements BLE device discovery using `QBluetoothDeviceDiscoveryAgent`.
- `BLERemoteDevice` manages connection and service/characteristic discovery for a specific BLE device.
- Designed to eventually support controlling external cameras (like DJI Osmo) via BLE.

### 4. Platform Integration (`platform.h`, `wifi.h`)
- Provides abstraction for platform-specific features:
    - WiFi SSID and signal strength monitoring.
    - Battery level and thermal status.
    - Keeping the app running in the background on Android.

## Technical Details
- **Language**: C++20 and QML.
- **Framework**: Qt 6.x (using `QtQuick`, `QtGrpc`, `QtBluetooth`).
- **Build System**: CMake.
- **Android Support**: Includes JNI calls for WiFi and permission management.
