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

    CamerasBuiltin {
        id: builtinCameraSettings
        anchors.fill: parent
    }
}
