import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import StreamingSettingsController

ColumnLayout {
    spacing: 8

    StreamingSettingsController {
        id: settingsController

        onSettingsSaved: function(filePath) {
            console.log("Settings saved to:", filePath)
        }

        onSaveFailed: function(filePath, errorString) {
            console.warn("Failed to save settings to", filePath, "error:", errorString)
        }
    }

    // Optional: status row
    RowLayout {
        Layout.fillWidth: true

        Label {
            text: settingsController.active ? "Status: Active" : "Status: Inactive"
            color: "#ffffff"
            font.pointSize: 16
            Layout.alignment: Qt.AlignVCenter
        }
    }

    RowLayout {
        Layout.fillWidth: true

        SpinBox {
            id: widthSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 160
            to: 3840
            stepSize: 16

            value: settingsController.width
            onValueModified: settingsController.width = value

            textFromValue: function (v) {
                return v + " px";
            }
        }

        Label {
            text: "x"
            color: "#ffffff"
            font.pointSize: 20
        }

        SpinBox {
            id: heightSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 120
            to: 2160
            stepSize: 16

            value: settingsController.height
            onValueModified: settingsController.height = value

            textFromValue: function (v) {
                return v + " px";
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "FPS"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: fpsSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 5
            to: 60
            value: settingsController.fps

            onValueModified: settingsController.fps = value
            stepSize: 1
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Bitrate (Kbps)"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: bitrateSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 256
            to: 20000
            value: settingsController.bitrateKbps

            onValueModified: settingsController.bitrateKbps = value
            stepSize: 256
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Preferred camera"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: cameraCombo
            Layout.fillWidth: true
            font.pointSize: 20
            model: ["Front", "Back"]

            // Synchronize with controller
            Component.onCompleted: {
                currentIndex = settingsController.preferredCamera === "Back" ? 1 : 0
            }

            onActivated: function(index) {
                settingsController.preferredCamera = (index === 1) ? "Back" : "Front"
            }

            // Also handle external changes (e.g. loaded from file)
            Connections {
                target: settingsController
                function onPreferredCameraChanged() {
                    cameraCombo.currentIndex =
                        settingsController.preferredCamera === "Back" ? 1 : 0
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Button {
            Layout.fillWidth: true
            font.pointSize: 20
            text: settingsController.active ? "Re-Activate" : "Activate"

            onClicked: {
                const ok = settingsController.activate()
                console.log("activate() returned:", ok,
                            "path:", settingsController.settingsFilePath)
            }
        }

        Button {
            Layout.fillWidth: true
            font.pointSize: 20
            text: "Deactivate"
            enabled: settingsController.active

            onClicked: {
                const ok = settingsController.deactivate()
                console.log("deactivate() returned:", ok)
            }
        }
    }
}