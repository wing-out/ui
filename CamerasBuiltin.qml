import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    spacing: 8

    RowLayout {
        Layout.fillWidth: true

        SpinBox {
            Layout.fillWidth: true
            font.pointSize: 20
            from: 160
            to: 3840
            stepSize: 16
            value: 1920
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
            Layout.fillWidth: true
            font.pointSize: 20
            from: 120
            to: 2160
            stepSize: 16
            value: 1080
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
            Layout.fillWidth: true
            font.pointSize: 20
            from: 5
            to: 60
            value: 60
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
            Layout.fillWidth: true
            font.pointSize: 20
            from: 256
            to: 20000
            value: 8000
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
            Layout.fillWidth: true
            font.pointSize: 20
            model: ["Front", "Back"]
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Button {
            Layout.fillWidth: true
            font.pointSize: 20
            text: "Activate"
        }
    }
}
