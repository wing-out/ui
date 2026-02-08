/* This file implements the main UI content for WingOut. */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore

import QtGrpc

import streamd 1.0 as StreamD
import ffstream_grpc 1.0 as FFStream

Pane {
    id: main
    anchors.fill: parent
    padding: 0

    property var applicationWindow: Window.window
    property string dxProducerHost: ""

    property bool locked: false
    readonly property bool isLandscape: width > height

    // Retrieve safe area insets from the platform when available.
    property var safeAreaInsets: (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }
    onWidthChanged: safeAreaInsets = (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }
    onHeightChanged: safeAreaInsets = (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }

    readonly property real safeAreaTop: ((safeAreaInsets && safeAreaInsets.top) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaBottom: ((safeAreaInsets && safeAreaInsets.bottom) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaLeft: ((safeAreaInsets && safeAreaInsets.left) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaRight: ((safeAreaInsets && safeAreaInsets.right) || 0) / Screen.devicePixelRatio

    topPadding: safeAreaTop
    leftPadding: safeAreaLeft
    rightPadding: safeAreaRight
    bottomPadding: safeAreaBottom

    ListModel {
        id: globalChatMessagesModel
    }

    // Use proper QML GrpcCallOptions objects instead of plain JS
    // objects: Qt 6.9 gRPC methods expect QQmlGrpcCallOptions* and
    // cannot convert from a V4ReferenceObject (JS {}).
    GrpcCallOptions {
        id: grpcCallOptions
        deadlineTimeout: 10000
    }
    GrpcCallOptions {
        id: streamingGrpcCallOptions
        deadlineTimeout: 365 * 24 * 3600 * 1000
    }

    // Create a real gRPC HTTP/2 channel for the ffstream connection.
    // Same pattern as the streamd channel (dxProducerChannel).
    GrpcHttp2Channel {
        id: ffstreamChannel
        hostUri: "http://localhost:3593"
    }

    FFStream.Client {
        id: ffstreamClient
        channel: ffstreamChannel.channel
        Component.onCompleted: {
            console.log("ffstreamClient connected to http://localhost:3593");
        }
    }

    function processStreamDGRPCError(dxProducer, error) {
        console.log("StreamD gRPC error:", JSON.stringify(error));
        if (dxProducer.processGRPCError !== undefined) {
            dxProducer.processGRPCError(error);
        }
    }

    function processFFStreamGRPCError(ffstream, error) {
        console.log("FFStream gRPC error:", JSON.stringify(error));
        if (ffstream.processGRPCError !== undefined) {
            ffstream.processGRPCError(error);
        }
    }

    // fireMultiPlatformRPC fires an RPC across all platforms with shared
    // success/error counting and status reporting.
    //   label: display name (e.g. "Shoutout", "Raid", "Title")
    //   rpcCall: function(platID, onSuccess, onError) that initiates the RPC
    //   setStatus: function(text) to update status text
    //   setStatusColor: function(colorStr) to update status color
    function fireMultiPlatformRPC(label, rpcCall, setStatus, setStatusColor) {
        var platforms = ["twitch", "youtube", "kick"];
        setStatus("Sending " + label.toLowerCase() + "...");
        setStatusColor("#FFFF00");
        var successCount = 0;
        var errorCount = 0;
        var total = platforms.length;
        for (var i = 0; i < platforms.length; i++) {
            (function(platID) {
                rpcCall(platID,
                    function() {
                        successCount++;
                        if (successCount + errorCount === total) {
                            setStatus(label + " sent (" + successCount + "/" + total + " ok)");
                            setStatusColor(errorCount === 0 ? "#00FF00" : "#FFFF00");
                        }
                    },
                    function(error) {
                        errorCount++;
                        console.warn(label + " failed for", platID, error);
                        if (successCount + errorCount === total) {
                            setStatus(successCount > 0
                                ? label + " partial (" + successCount + "/" + total + ")"
                                : label + " failed");
                            setStatusColor(successCount > 0 ? "#FFFF00" : "#FF0000");
                        }
                        processStreamDGRPCError(dxProducerClient, error);
                    });
            })(platforms[i]);
        }
    }

    QtObject {
        id: platform
        property real cpuUtilization: 0.0
        property real memoryUtilization: 0.0
        property var temperatures: []
        property bool isHotspotEnabled: false
        property bool isLocalHotspotEnabled: false
        property string hotspotIPAddress: ""
        function getSafeAreaInsets() {
            return {
                top: 0,
                bottom: 0,
                left: 0,
                right: 0
            };
        }
        function setEnableRunningInBackground(v) { /* stub */
        }
        function startMonitoringSignalStrength() { /* stub */
        }
        function refreshWiFiState() { /* stub */
        }
        function startWiFiScan() { /* stub */
        }
        function updateResources() { /* stub */
        }
        function getCurrentWiFiConnection() {
            return {
                ssid: "",
                bssid: "",
                rssi: -32768
            };
        }
        function getChannelsQualityInfo() {
            return [];
        }
        function getLocalOnlyHotspotInfo() {
            return {
                ssid: "",
                psk: ""
            };
        }
        function getHotspotConfiguration() {
            return {
                ssid: "",
                psk: ""
            };
        }
        function saveHotspotConfiguration(ssid, psk) { /* stub */
        }
        function setHotspotEnabled(enabled) {
            isHotspotEnabled = enabled;
        }
        function setLocalHotspotEnabled(enabled) {
            isLocalHotspotEnabled = enabled;
        }
        function vibrate(ms, fallback) { /* stub */
        }
        signal signalStrengthChanged(int strength)
    }

    Connections {
        target: main.applicationWindow
        function onClosing(close) {
            close.accepted = false;
            main.locked = true;
        }
    }

    Component.onCompleted: {
        if (platform && typeof platform.refreshWiFiState === 'function')
            platform.refreshWiFiState();
    }

    // Create a real gRPC HTTP/2 channel for the streamd connection.
    // DXProducer::Client._onChannelChanged() extracts the hostUri,
    // disables SSL peer verification, and re-creates the channel.
    GrpcHttp2Channel {
        id: dxProducerChannel
        hostUri: main.dxProducerHost
    }

    StreamD.Client {
        id: dxProducerClient
        channel: dxProducerChannel.channel
        Component.onCompleted: {
            console.log("dxProducerClient connected to", main.dxProducerHost);
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

    SwipeLockOverlay {
        id: lockOverlay
        locked: main.locked
        topPadding: main.safeAreaTop
        onUnlockRequested: main.locked = false
    }

    Button {
        id: lockButton
        visible: !main.locked && stack.currentIndex === 0
        text: "🔒"
        anchors.top: stack.top
        anchors.right: stack.right
        anchors.margins: 16
        font.pixelSize: 40
        property real defaultOpacity: 0.7
        opacity: hovered ? 1.0 : defaultOpacity
        onClicked: main.locked = true
    }
}
