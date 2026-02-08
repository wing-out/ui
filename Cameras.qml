pragma ComponentBehavior: Bound
import QtCore
/* This file implements the Cameras page for monitoring camera feeds. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import RemoteCameraController

Page {
    id: camerasPage
    required property var root
    Material.theme: Material.Dark
    Material.accent: Material.Purple

    property var streamSources: []
    property var streamServers: []

    function refresh() {
        console.log("Cameras.qml: Requesting stream sources and servers...");
        if (!camerasPage.root.checkStreamDClient()) {
            return;
        }
        camerasPage.root.dxProducerClient.listStreamSources(function (response) {
            console.log("Cameras.qml: Received stream sources response: " + JSON.stringify(response));
            camerasPage.streamSources = response.streamSourcesData || response.streamSources || [];
        }, function (error) {
            console.log("Cameras.qml: Error listing stream sources");
            camerasPage.root.processStreamDGRPCError(camerasPage.root.dxProducerClient, error);
        }, camerasPage.root.grpcCallOptions);

        camerasPage.root.dxProducerClient.listStreamServers(function (response) {
            console.log("Cameras.qml: Received stream servers response: " + JSON.stringify(response));
            camerasPage.streamServers = response.streamServersData || response.streamServers || [];
        }, function (error) {
            console.log("Cameras.qml: Error listing stream servers");
            camerasPage.root.processStreamDGRPCError(camerasPage.root.dxProducerClient, error);
        }, camerasPage.root.grpcCallOptions);
    }

    Component.onCompleted: refresh()

    Column {
        anchors.fill: parent
        spacing: 20

        Label {
            text: "Stream Sources"
            font.bold: true
            font.pointSize: 16
        }

        ListView {
            width: parent.width
            height: 200
            model: camerasPage.streamSources
            clip: true
            delegate: ItemDelegate {
                width: parent.width
                text: modelData.streamSourceID + (modelData.isActive ? " (Active)" : " (Inactive)")
            }
        }

        Label {
            text: "Stream Servers"
            font.bold: true
            font.pointSize: 16
        }

        ListView {
            width: parent.width
            height: 200
            model: camerasPage.streamServers
            clip: true
            delegate: ItemDelegate {
                width: parent.width
                text: modelData.config.listenAddr
            }
        }

        Button {
            text: "Refresh"
            onClicked: refresh()
        }
    }

    /*
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
        anchors.top: parent.top
    }
    */
}
