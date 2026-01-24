/* This file implements the main application window and global gRPC setup for WingOut. */
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtGrpc
import Platform

import streamd as StreamD
import ffstream_grpc as FFStream

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out")

    property bool locked: false
    readonly property bool isLandscape: width > height

    property var safeAreaInsets: platform.getSafeAreaInsets()
    onWidthChanged: safeAreaInsets = platform.getSafeAreaInsets()
    onHeightChanged: safeAreaInsets = platform.getSafeAreaInsets()

    readonly property real safeAreaTop: ((safeAreaInsets && safeAreaInsets.top) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaBottom: ((safeAreaInsets && safeAreaInsets.bottom) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaLeft: ((safeAreaInsets && safeAreaInsets.left) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaRight: ((safeAreaInsets && safeAreaInsets.right) || 0) / Screen.devicePixelRatio

    ListModel {
        id: globalChatMessagesModel
    }

    topPadding: safeAreaTop
    leftPadding: safeAreaLeft
    rightPadding: safeAreaRight
    bottomPadding: safeAreaBottom

    GrpcCallOptions {
        id: grpcCallOptions
        deadlineTimeout: 10000
    }
    GrpcCallOptions {
        id: streamingGrpcCallOptions
        deadlineTimeout: 365 * 24 * 3600 * 1000
    }
    GrpcHttp2Channel {
        id: dxProducerTarget
        hostUri: "http://192.168.0.134:3594"
        options: GrpcChannelOptions {
            deadlineTimeout: 365 * 24 * 3600 * 1000
        }
    }
    StreamD.Client {
        id: dxProducerClient
        channel: dxProducerTarget.channel
        Component.onCompleted: {
            console.log("dxProducerClient connected to", dxProducerTarget.hostUri);
        }
    }
    GrpcHttp2Channel {
        id: ffstreamTarget
        hostUri: "http://localhost:3593"
        options: GrpcChannelOptions {
            deadlineTimeout: 365 * 24 * 3600 * 1000
        }
    }
    FFStream.Client {
        id: ffstreamClient
        channel: ffstreamTarget.channel
    }

    function processStreamDGRPCError(dxProducer, error): void {
        console.log("StreamD gRPC error:", JSON.stringify(error));
        if (dxProducer.processGRPCError !== undefined) {
            dxProducer.processGRPCError(error);
        }
    }

    function processFFStreamGRPCError(ffstream, error): void {
        console.log("FFStream gRPC error:", JSON.stringify(error));
        if (ffstream.processGRPCError !== undefined) {
            ffstream.processGRPCError(error);
        }
    }

    Component.onCompleted: {
        console.log("ApplicationWindow completed");
    }

    Platform {
        id: platform
        Component.onCompleted: {
            platform.setEnableRunningInBackground(true);
            platform.startMonitoringSignalStrength();
            platform.refreshWiFiState();
        }
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) {
                console.log("Application active, refreshing WiFi state");
                platform.refreshWiFiState();
            }
        }
    }

    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: 0

        Dashboard {
            id: dashboardPage
        }
        Cameras {
            id: camerasPage
        }
        DJIControl {
            id: djiControlPage
            Component.onCompleted: console.log("DJIControl page completed")
        }
        Chat {
            id: chatPage
        }
        Players {
            id: playersPage
        }
        Restreams {
            id: restreamsPage
        }
        Monitor {
            id: monitorPage
        }
        Profiles {
            id: profilesPage
        }
        Settings {
            id: settingsPage
        }
    }

    RoundButton {
        id: menuButton
        text: "☰"
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 56
        height: 56
        font.pixelSize: 24
        z: 100
        highlighted: true
        Material.elevation: 6
        onClicked: navMenu.open()
    }

    Menu {
        id: navMenu
        y: menuButton.y + menuButton.height
        x: menuButton.x - (width / 2) + (menuButton.width / 2)

        MenuItem {
            text: "Dashboard"
            onTriggered: stack.currentIndex = 0
        }
        MenuItem {
            text: "Cameras"
            onTriggered: stack.currentIndex = 1
        }
        MenuItem {
            text: "DJI"
            onTriggered: stack.currentIndex = 2
        }
        MenuItem {
            text: "Chat"
            onTriggered: stack.currentIndex = 3
        }
        MenuItem {
            text: "Players"
            onTriggered: stack.currentIndex = 4
        }
        MenuItem {
            text: "Restreams"
            onTriggered: stack.currentIndex = 5
        }
        MenuItem {
            text: "Monitor"
            onTriggered: stack.currentIndex = 6
        }
        MenuItem {
            text: "Profiles"
            onTriggered: stack.currentIndex = 7
        }
        MenuItem {
            text: "Settings"
            onTriggered: stack.currentIndex = 8
        }
    }

    onClosing: close => {
        close.accepted = false;
        application.locked = true;
    }

    SwipeLockOverlay {
        id: lockOverlay
        locked: application.locked
        topPadding: application.safeAreaTop
        onUnlockRequested: application.locked = false
    }

    Button {
        id: lockButton
        visible: !application.locked && stack.currentIndex === 0
        text: "🔒"
        anchors.top: stack.top
        anchors.right: stack.right
        anchors.margins: 16
        font.pixelSize: 40
        property real defaultOpacity: 0.7
        opacity: hovered ? 1.0 : defaultOpacity
        onClicked: application.locked = true
    }
}
