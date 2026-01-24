import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RemoteCameraController

Page {
    id: djiControlPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple

    property bool flowStarted: false
    property bool streamingButtonCooldown: false
    property int hotspotInfoRetryCount: 0

    Timer {
        id: streamingCooldownTimer
        interval: 10000
        repeat: false
        onTriggered: streamingButtonCooldown = false
    }

    Timer {
        id: hotspotInfoTimer
        interval: 2000
        repeat: false
        onTriggered: {
            platform.refreshWiFiState()
            var isLocal = platform.isLocalHotspotEnabled
            var isNormal = platform.isHotspotEnabled
            var info = isLocal ? platform.getLocalOnlyHotspotInfo() : (isNormal ? platform.getHotspotConfiguration() : null)

            if (info && info.ssid) {
                wifiSsidField.text = info.ssid
                wifiPskField.text = info.psk
                console.log("[DJI-BLE] QML: Auto-filled from hotspot (auto):", info.ssid)
                hotspotInfoRetryCount = 0
            } else if (isLocal || isNormal) {
                if (hotspotInfoRetryCount < 5) {
                    hotspotInfoRetryCount++
                    console.log("[DJI-BLE] QML: Hotspot info not ready, retrying (" + hotspotInfoRetryCount + "/5)...")
                    hotspotInfoTimer.start()
                } else {
                    DJIController.error("Failed to auto-fill hotspot info after retries")
                    hotspotInfoRetryCount = 0
                }
            }
        }
    }

    Connections {
        target: platform
        function onIsLocalHotspotEnabledChanged() {
            if (platform.isLocalHotspotEnabled) {
                console.log("[DJI-BLE] QML: Local hotspot enabled, starting auto-fill timer...")
                hotspotInfoRetryCount = 0
                hotspotInfoTimer.start()
            }
        }
        function onIsHotspotEnabledChanged() {
            if (platform.isHotspotEnabled) {
                console.log("[DJI-BLE] QML: Hotspot enabled, starting auto-fill timer...")
                hotspotInfoRetryCount = 0
                hotspotInfoTimer.start()
            }
        }
    }

    Connections {
        target: DJIController
        function onIsPairedChanged() {
            if (DJIController.isPaired && !djiControlPage.flowStarted) {
                djiControlPage.flowStarted = true
                console.log("[DJI-BLE] QML: Device paired. Starting flow in 1s...")
                startFlowTimer.start()
            }
        }
        function onLog(msg) {
            console.log("[DJI-BLE] QML:", msg)
            logArea.append("[LOG] " + msg)
        }
        function onError(msg) {
            console.error("[DJI-BLE] QML Error:", msg)
            logArea.append("[ERROR] " + msg)
        }
    }

    Timer {
        id: startFlowTimer
        interval: 1000
        repeat: false
        onTriggered: {
            var res = resolutionSelector.currentIndex === 0 ? 1080 : (resolutionSelector.currentIndex === 1 ? 720 : 480)
            var fps = parseInt(fpsSelector.currentText)
            console.log("[DJI-BLE] QML: Actually starting streaming to", rtmpUrlField.text)
            DJIController.startStreaming(rtmpUrlField.text, res, fps, bitrateSelector.value)
        }
    }


    Connections {
        target: DJIController
        function onDevicesUpdated() {
            if (DJIController.device === null) {
                var list = DJIController.devicesList
                for (var i = 0; i < list.length; ++i) {
                    var dev = list[i]
                    // Auto-select if it's identified as a DJI device (even if type is Unknown)
                    console.log("[DJI-BLE] QML: Auto-selecting device:", dev.name)
                    DJIController.device = dev
                    break
                }
            }
        }
    }

    Component.onCompleted: {
        console.log("[DJI-BLE] QML: Starting auto-discovery...")
        DJIController.startDeviceDiscovery()

        platform.refreshWiFiState()
        var hotspot = platform.isLocalHotspotEnabled ? platform.getLocalOnlyHotspotInfo() : platform.getHotspotConfiguration()
        if (hotspot && hotspot.ssid) {
            console.log("[DJI-BLE] QML: Auto-filled hotspot info for SSID:", hotspot.ssid)
            wifiSsidField.text = hotspot.ssid
            wifiPskField.text = hotspot.psk
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent

        ColumnLayout {
            id: mainLayout
            width: scrollView.availableWidth - 40
            x: 20
            y: 20
            spacing: 20

            ComboBox {
                id: deviceSelector
                Layout.fillWidth: true
                model: DJIController.devicesList
                textRole: "name"
                onCurrentIndexChanged: {
                    if (currentIndex >= 0) {
                        DJIController.device = model[currentIndex]
                    }
                }
            }

        GroupBox {
            title: "WiFi Settings"
            Layout.fillWidth: true
            enabled: DJIController.device !== null

            ColumnLayout {
                anchors.fill: parent
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Hotspot:"
                    }
                    Switch {
                        id: hotspotSwitch
                        checked: platform.isHotspotEnabled
                        enabled: !localHotspotSwitch.checked
                        onToggled: {
                            platform.setHotspotEnabled(checked)
                        }
                    }
                    Label {
                        text: "Local Hotspot:"
                    }
                    Switch {
                        id: localHotspotSwitch
                        checked: platform.isLocalHotspotEnabled
                        enabled: !hotspotSwitch.checked
                        onToggled: {
                            platform.setLocalHotspotEnabled(checked)
                        }
                    }
                }
                TextField {
                    id: wifiSsidField
                    placeholderText: "WiFi SSID"
                    text: ""
                    Layout.fillWidth: true
                }
                TextField {
                    id: wifiPskField
                    placeholderText: "WiFi PSK"
                    text: ""
                    echoMode: TextInput.Password
                    Layout.fillWidth: true
                }
                Button {
                    text: "Fill from Hotspot"
                    Layout.fillWidth: true
                    onClicked: {
                        platform.refreshWiFiState()
                        var info = localHotspotSwitch.checked ? platform.getLocalOnlyHotspotInfo() : platform.getHotspotConfiguration()
                        if (info && info.ssid) {
                            wifiSsidField.text = info.ssid
                            wifiPskField.text = info.psk
                        } else {
                            DJIController.error("Failed to get hotspot info")
                        }
                    }
                }
            }
        }

        GroupBox {
            title: "Streaming Settings"
            Layout.fillWidth: true
            enabled: DJIController.device !== null

            ColumnLayout {
                anchors.fill: parent
                TextField {
                    id: rtmpUrlField
                    placeholderText: "RTMP URL"
                    text: {
                        var ip = platform.hotspotIPAddress
                        if (!ip) ip = DJIController.localWlan1Ip
                        return ip ? "rtmp://" + ip + ":1935/proxy/dji-osmo-pocket3" : ""
                    }
                    Layout.fillWidth: true
                }

                RowLayout {
                    Label { text: "Res:" }
                    ComboBox {
                        id: resolutionSelector
                        model: ["1080p", "720p", "480p"]
                        Layout.fillWidth: true
                    }
                    Label { text: "FPS:" }
                    ComboBox {
                        id: fpsSelector
                        model: ["30", "25"]
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Label { text: "Bitrate (Kbps):" }
                    SpinBox {
                        id: bitrateSelector
                        from: 500
                        to: 20000
                        value: 3000
                        stepSize: 500
                        editable: true
                        Layout.fillWidth: true
                    }
                }
            }
        }

        Button {
            text: DJIController.isStreaming ? "Stop Streaming" : "Start Streaming"
            Layout.fillWidth: true
            onClicked: {
                streamingButtonCooldown = true
                streamingCooldownTimer.start()
                if (DJIController.isStreaming) {
                    DJIController.stopStreaming()
                } else {
                    var res = resolutionSelector.currentIndex === 0 ? 1080 : (resolutionSelector.currentIndex === 1 ? 720 : 480)
                    var fps = parseInt(fpsSelector.currentText)
                    DJIController.wifiSSID = wifiSsidField.text
                    DJIController.wifiPSK = wifiPskField.text
                    platform.saveHotspotConfiguration(wifiSsidField.text, wifiPskField.text)
                    DJIController.startStreaming(rtmpUrlField.text, res, fps, bitrateSelector.value)
                }
            }
            enabled: !streamingButtonCooldown && (DJIController.isStreaming || (DJIController.device !== null && wifiSsidField.text !== "" && wifiPskField.text !== "" && rtmpUrlField.text !== ""))
        }

        TextArea {
            id: logArea
            Layout.fillWidth: true
            readOnly: true
            font.family: "Monospace"
            text: "Waiting for device..."
            wrapMode: TextEdit.Wrap
        }

        Item {
            Layout.preferredHeight: 20
            Layout.fillWidth: true
        }
    }
}
}
