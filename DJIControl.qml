import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RemoteCameraController

Page {
    id: djiControlPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("DJI Control")

    property bool flowStarted: false
    property bool streamingButtonCooldown: false

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
            var info = platform.getLocalOnlyHotspotInfo()
            if (info && info.ssid) {
                wifiSsidField.text = info.ssid
                wifiPskField.text = info.psk
                console.log("[DJI-BLE] QML: Auto-filled from local hotspot (auto):", info.ssid)
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
        function onLog(msg) { console.log("[DJI-BLE] QML:", msg) }
        function onError(msg) { console.error("[DJI-BLE] QML Error:", msg) }
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

        var hotspot = platform.getHotspotConfiguration()
        if (hotspot && hotspot.ssid) {
            console.log("[DJI-BLE] QML: Auto-filled hotspot info for SSID:", hotspot.ssid)
            wifiSsidField.text = hotspot.ssid
            wifiPskField.text = hotspot.psk
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Label {
            text: "DJI Osmo Control"
            font.pointSize: 24
            Layout.alignment: Qt.AlignHCenter
        }

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
                        onToggled: platform.setHotspotEnabled(checked)
                    }
                    Label {
                        text: "Local Hotspot:"
                    }
                    Switch {
                        id: localHotspotSwitch
                        checked: platform.isLocalHotspotEnabled
                        onToggled: {
                            platform.setLocalHotspotEnabled(checked)
                            if (checked) hotspotInfoTimer.start()
                        }
                    }
                }
                Button {
                    text: "Auto-fill from Local Hotspot"
                    Layout.fillWidth: true
                    onClicked: {
                        var info = platform.getLocalOnlyHotspotInfo()
                        if (info && info.ssid) {
                            wifiSsidField.text = info.ssid
                            wifiPskField.text = info.psk
                            console.log("[DJI-BLE] QML: Auto-filled from local hotspot:", info.ssid)
                        } else {
                            console.log("[DJI-BLE] QML: No local hotspot info available")
                        }
                    }
                    enabled: localHotspotSwitch.checked
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
                    text: DJIController.localWlan1Ip ? "rtmp://" + DJIController.localWlan1Ip + ":1935/proxy/dji-osmo-pocket3" : ""
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
                        value: 10000
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

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            TextArea {
                id: logArea
                readOnly: true
                font.family: "Monospace"
                text: "Waiting for device..."
            }
        }
    }
}
