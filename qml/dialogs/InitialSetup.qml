import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components" as Components
import WingOut

Rectangle {
    id: root
    color: Theme.background

    Accessible.name: "initialSetup"
    Accessible.role: Accessible.Dialog

    signal setupComplete(string host, string mode, string ffstreamAddr, string streamdAddr)

    property string selectedMode: "embedded"

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.spacingLarge * 2, 500)
        spacing: Theme.spacingLarge

        Text {
            text: "Welcome to WingOut"
            font.pixelSize: Theme.fontHuge
            font.weight: Font.Bold
            color: Theme.accentPrimary
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Configure your streaming backend to get started"
            font.pixelSize: Theme.fontMedium
            color: Theme.textSecondary
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Item { width: 1; height: Theme.spacingMedium }

        // Backend host
        Components.GlassCard {
            width: parent.width

            Column {
                id: setupCol
                width: parent.width
                spacing: Theme.spacingMedium

                Text {
                    text: "Mode"
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Row {
                    spacing: Theme.spacingSmall

                    Components.GlassButton {
                        text: "Embedded"
                        filled: root.selectedMode === "embedded"
                        onClicked: root.selectedMode = "embedded"
                    }
                    Components.GlassButton {
                        text: "Remote"
                        filled: root.selectedMode === "remote"
                        onClicked: root.selectedMode = "remote"
                    }
                    Components.GlassButton {
                        text: "Hybrid"
                        filled: root.selectedMode === "hybrid"
                        onClicked: root.selectedMode = "hybrid"
                    }
                }

                Text {
                    visible: root.selectedMode === "remote"
                    text: "WingOut Server Address"
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Components.SearchField {
                    id: hostField
                    objectName: "hostField"
                    visible: root.selectedMode === "remote"
                    width: parent.width
                    placeholder: "e.g. 127.0.0.1:3595"
                }

                Text {
                    text: "FFStream Address"
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Components.SearchField {
                    id: ffstreamAddrField
                    objectName: "ffstreamAddrField"
                    width: parent.width
                    placeholder: "e.g. 127.0.0.1:3593"
                }

                Text {
                    text: "StreamD Address"
                    font.pixelSize: Theme.fontSmall
                    font.weight: Font.Medium
                    color: Theme.textSecondary
                }

                Components.SearchField {
                    id: streamdAddrField
                    objectName: "streamdAddrField"
                    width: parent.width
                    placeholder: "e.g. 127.0.0.1:3594"
                }

            }
        }

        Components.GlassButton {
            objectName: "connectButton"
            text: "Connect"
            filled: true
            width: parent.width
            enabled: hostField.text.length > 0 || root.selectedMode === "embedded" || root.selectedMode === "hybrid"
            onClicked: {
                var host = hostField.text.trim()
                if ((root.selectedMode === "embedded" || root.selectedMode === "hybrid") && host === "") {
                    host = "127.0.0.1:3595"
                }
                root.setupComplete(host, root.selectedMode,
                    ffstreamAddrField.text.trim(), streamdAddrField.text.trim())
            }
        }
    }
}
