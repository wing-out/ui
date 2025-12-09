import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import RemoteCameraController

Page {
    id: application
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Cameras")

    BluetoothPermission {
        id: bluetoothPermission
        communicationModes: BluetoothPermission.Access
        onStatusChanged: {
            switch (bluetoothPermission.status) {
            case Qt.PermissionStatus.Denied:
                break;
            case Qt.PermissionStatus.Granted:
                break;
            }
        }
    }

    Label {
        id: builtinCameraLabel
        text: "Built-in Camera"
        color: "#ffffff"
        font.pointSize: 24
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
    }
    CamerasBuiltin {
        id: builtinCameraSettings
        anchors.top: builtinCameraLabel.bottom
    }
}
