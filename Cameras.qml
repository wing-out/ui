pragma ComponentBehavior: Bound
import QtCore
/* This file implements the Cameras page for monitoring camera feeds. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import RemoteCameraController

Page {
    id: camerasPage
    required property var root
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    // NO Page bottomPadding here: AndroidManifest sets
    // windowSoftInputMode=adjustResize, so Android already resizes the
    // app window when the on-screen keyboard appears. Adding a Page-level
    // bottomPadding bound to Qt.inputMethod.keyboardRectangle.height
    // double-shrinks the content (window already smaller +
    // bottomPadding pushes contentItem's bottom up by another keyboard
    // height) and collapses the inner ScrollView to ~0 height — the
    // user can't see anything between the pinned status and the pinned
    // Activate buttons. The CamerasBuiltin ScrollView's
    // scrollOutputUrlIntoView() handler (see CamerasBuiltin.qml) is the
    // correct mechanism: programmatic Flickable.contentY adjustment
    // when outputUrlField gains focus, so the field stays in view above
    // the keyboard without doubling the layout shrink.

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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Tab order: Built-in first (default-selected on launch — the
        // primary path most users take after the camera-pages
        // consolidation that moved every camera + codec setting into
        // the Built-in tab), Network second (informational stream-source
        // / server listings).
        TabBar {
            id: camerasTabBar
            Layout.fillWidth: true

            TabButton {
                text: "Built-in"
            }
            TabButton {
                text: "Network"
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: camerasTabBar.currentIndex

            // Built-in tab — index 0, default selected. Camera + codec +
            // outputUrl + Activate/Deactivate all live here post the
            // camera-pages consolidation.
            CamerasBuiltin {
                id: builtinCameraSettings
                root: camerasPage.root
            }

            // Network tab — index 1. Read-only stream-source / server
            // listings from dx-producer.
            Column {
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
                    onClicked: camerasPage.refresh()
                }
            }
        }
    }
}
