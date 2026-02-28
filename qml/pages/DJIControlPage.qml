import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "djiControlPage"
    Accessible.role: Accessible.Pane

    property var djiController: null
    property bool isPaired: false
    property bool isWiFiConnected: false
    property bool isStreaming: false
    property string wifiSSID: ""
    property string wifiPSK: ""
    property string rtmpUrl: ""
    property string resolution: "1080p"
    property int fps: 30
    property int bitrateMbps: 8
    property string logText: ""

    function appendLog(msg) {
        var ts = new Date().toLocaleTimeString()
        root.logText = "[" + ts + "] " + msg + "\n" + root.logText
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: Theme.spacingMedium

            Text {
                text: "DJI Camera Control"
                Accessible.name: "DJI Camera Control"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            // Connection status
            Components.GlassCard {
                width: parent.width
                implicitHeight: statusCol.implicitHeight + Theme.spacingLarge * 2

                Column {
                    id: statusCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Row {
                        spacing: Theme.spacingSmall
                        Components.StatusBadge {
                            label: root.isPaired ? "Paired" : "Not Paired"
                            statusColor: root.isPaired ? Theme.success : Theme.error
                        }
                        Components.StatusBadge {
                            label: root.isWiFiConnected ? "WiFi" : "No WiFi"
                            statusColor: root.isWiFiConnected ? Theme.success : Theme.warning
                        }
                        Components.StatusBadge {
                            label: root.isStreaming ? "Streaming" : "Idle"
                            statusColor: root.isStreaming ? Theme.success : Theme.textTertiary
                            active: root.isStreaming
                        }
                    }

                    Text {
                        text: root.wifiSSID !== "" ? "WiFi: " + root.wifiSSID : "No WiFi network"
                        Accessible.name: root.wifiSSID !== "" ? "WiFi: " + root.wifiSSID : "No WiFi network"
                        font.pixelSize: Theme.fontMedium
                        color: Theme.textSecondary
                    }
                }
            }

            // Discovery / Disconnect button
            Components.GlassButton {
                objectName: "djiDiscoveryButton"
                text: root.isPaired ? "Disconnect" : "Start Discovery"
                filled: true
                width: parent.width
                onClicked: {
                    if (root.djiController) {
                        if (root.isPaired) {
                            root.djiController.disconnect()
                            root.appendLog("Disconnecting...")
                        } else {
                            root.djiController.startDiscovery()
                            root.appendLog("Starting discovery...")
                        }
                    } else {
                        root.isPaired = !root.isPaired
                        root.appendLog(root.isPaired ? "Simulated pairing" : "Simulated disconnect")
                    }
                }
            }

            // WiFi Settings
            Text {
                text: "WiFi Settings"
                Accessible.name: "WiFi Settings"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: wifiCol.implicitHeight + Theme.spacingLarge * 2

                Column {
                    id: wifiCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Text {
                        text: "SSID"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: ssidField
                        objectName: "djiSsidField"
                        width: parent.width
                        placeholder: "WiFi network name"
                        text: root.wifiSSID
                        onTextChanged: root.wifiSSID = text
                    }

                    Text {
                        text: "Password"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: pskField
                        objectName: "djiPskField"
                        width: parent.width
                        placeholder: "WiFi password"
                        text: root.wifiPSK
                        onTextChanged: root.wifiPSK = text
                    }

                    Components.GlassButton {
                        objectName: "djiConnectWifiButton"
                        text: root.isWiFiConnected ? "Disconnect WiFi" : "Connect WiFi"
                        filled: true
                        width: parent.width
                        onClicked: {
                            if (root.isWiFiConnected) {
                                root.isWiFiConnected = false
                                root.appendLog("WiFi disconnected")
                            } else if (root.wifiSSID !== "") {
                                root.isWiFiConnected = true
                                root.appendLog("Connected to " + root.wifiSSID)
                            }
                        }
                    }
                }
            }

            // Streaming RTMP URL
            Text {
                text: "Streaming"
                Accessible.name: "Streaming"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: streamCol.implicitHeight + Theme.spacingLarge * 2

                Column {
                    id: streamCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Text {
                        text: "RTMP URL"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: rtmpField
                        objectName: "djiRtmpField"
                        width: parent.width
                        placeholder: "rtmp://..."
                        text: root.rtmpUrl
                        onTextChanged: root.rtmpUrl = text
                    }
                }
            }

            // Stream settings
            Text {
                text: "Stream Settings"
                Accessible.name: "Stream Settings"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: Theme.spacingSmall
                rowSpacing: Theme.spacingSmall

                Components.MetricTile {
                    objectName: "djiResolutionTile"
                    title: "Resolution"
                    value: root.resolution
                    Layout.fillWidth: true
                }
                Components.MetricTile {
                    objectName: "djiFpsTile"
                    title: "FPS"
                    value: root.fps.toString()
                    Layout.fillWidth: true
                }
                Components.MetricTile {
                    objectName: "djiBitrateTile"
                    title: "Bitrate"
                    value: root.bitrateMbps.toString()
                    unit: "Mbps"
                    Layout.fillWidth: true
                }
            }

            // Resolution selector
            Row {
                spacing: Theme.spacingSmall

                Text {
                    text: "Resolution:"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: ["720p", "1080p", "4K"]
                    Components.GlassButton {
                        objectName: "djiRes" + modelData
                        text: modelData
                        filled: root.resolution === modelData
                        onClicked: root.resolution = modelData
                    }
                }
            }

            // FPS selector
            Row {
                spacing: Theme.spacingSmall

                Text {
                    text: "FPS:"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: [24, 30, 60]
                    Components.GlassButton {
                        objectName: "djiFps" + modelData
                        text: modelData.toString()
                        filled: root.fps === modelData
                        onClicked: root.fps = modelData
                    }
                }
            }

            // Bitrate selector
            Row {
                spacing: Theme.spacingSmall

                Text {
                    text: "Bitrate (Mbps):"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: [4, 8, 12, 20]
                    Components.GlassButton {
                        objectName: "djiBitrate" + modelData
                        text: modelData.toString()
                        filled: root.bitrateMbps === modelData
                        onClicked: root.bitrateMbps = modelData
                    }
                }
            }

            // Start/Stop Streaming button
            Components.GlassButton {
                objectName: "djiStreamButton"
                text: root.isStreaming ? "Stop Streaming" : "Start Streaming"
                filled: true
                accentColor: root.isStreaming ? Theme.error : Theme.success
                width: parent.width
                enabled: root.isWiFiConnected
                onClicked: {
                    root.isStreaming = !root.isStreaming
                    root.appendLog(root.isStreaming ? "Streaming started" : "Streaming stopped")
                }
            }

            // Log area
            Text {
                text: "Log"
                Accessible.name: "Log"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 200

                Flickable {
                    anchors.fill: parent
                    contentHeight: logArea.implicitHeight
                    clip: true

                    Text {
                        id: logArea
                        objectName: "djiLogArea"
                        width: parent.width
                        text: root.logText !== "" ? root.logText : "No log entries yet."
                        Accessible.name: root.logText !== "" ? root.logText : "No log entries yet."
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
