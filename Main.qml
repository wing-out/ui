/* This file implements the main UI content for WingOut. */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtGrpc

import streamd 1.0 as StreamD
import ffstream_grpc 1.0 as FFStream
import Platform 1.0

Pane {
    id: main
    objectName: "main"
    anchors.fill: parent
    padding: 0

    property var applicationWindow: Window.window
    required property var platformInstance
    property var appSettings
    readonly property string dxProducerHost: appSettings ? appSettings.dxProducerHost : ""

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

    property alias ffstreamClient: ffstreamClient
    property alias dxProducerClient: dxProducerClient
    property alias globalChatMessagesModel: globalChatMessagesModel
    property alias grpcCallOptions: grpcCallOptions
    property alias streamingGrpcCallOptions: streamingGrpcCallOptions
    readonly property var platform: platformInstance

    function normalizeGrpcUri(rawValue, defaultScheme) {
        if (rawValue === undefined || rawValue === null) {
            return "";
        }
        var value = String(rawValue).trim();
        if (value.length === 0) {
            return "";
        }
        if (value.startsWith("tcp+ssl://")) {
            value = "https://" + value.substring("tcp+ssl://".length);
        } else if (value.startsWith("tcp+ssl:")) {
            value = "https://" + value.substring("tcp+ssl:".length);
        } else if (value.startsWith("tcp+insecure://")) {
            value = "http://" + value.substring("tcp+insecure://".length);
        } else if (value.startsWith("tcp+insecure:")) {
            value = "http://" + value.substring("tcp+insecure:".length);
        } else if (value.startsWith("tcp://")) {
            value = "http://" + value.substring("tcp://".length);
        } else if (value.startsWith("tcp:")) {
            value = "http://" + value.substring("tcp:".length);
        }
        if (!value.startsWith("http://") && !value.startsWith("https://")) {
            var scheme = defaultScheme && defaultScheme.length > 0 ? defaultScheme : "https";
            value = scheme + "://" + value;
        }
        return value;
    }

    readonly property string normalizedDxProducerHost: normalizeGrpcUri(appSettings ? appSettings.dxProducerHost : "", "https")
    // ffstreamHost must be configured explicitly. No host-derivation fallback —
    // we previously derived a URL from dxProducerHost when ffstreamHost was
    // empty, but that silently overrode the user's value during the brief
    // window when Core.Settings had not yet loaded persisted state, leaving
    // the ffstream client bound to the wrong host indefinitely.
    readonly property string normalizedFFStreamHost: normalizeGrpcUri(
        appSettings ? appSettings.ffstreamHost : "", "https")

    FFStream.Client {
        id: ffstreamClient
        Component.onCompleted: {
            if (main.normalizedFFStreamHost && main.normalizedFFStreamHost.length > 0) {
                ffstreamClient.setServerUri(main.normalizedFFStreamHost);
                console.log("ffstreamClient setServerUri:", main.normalizedFFStreamHost);
            }
        }
    }

    Connections {
        target: main
        function onNormalizedFFStreamHostChanged() {
            if (main.normalizedFFStreamHost && main.normalizedFFStreamHost.length > 0) {
                ffstreamClient.setServerUri(main.normalizedFFStreamHost);
                console.log("ffstreamClient setServerUri:", main.normalizedFFStreamHost);
            }
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

    function checkStreamDClient() {
        if (!dxProducerClient) {
            console.warn("Main.qml: StreamD client not initialized");
            return false;
        }
        return true;
    }

    function checkFFStreamClient() {
        if (!ffstreamClient) {
            console.warn("Main.qml: FFStream client not initialized");
            return false;
        }
        return true;
    }

    function withStreamClient(callback, onError, caller) {
        if (!dxProducerClient) {
            console.warn("Main.qml: StreamD client not initialized");
            if (onError) {
                onError("client not initialized");
            }
            return;
        }
        if (!dxProducerClient.isChannelReady()) {
            if (onError) {
                onError("channel not ready");
            }
            return;
        }
        callback(dxProducerClient);
    }

    function withFFStreamClient(callback, onError) {
        if (!ffstreamClient) {
            console.warn("Main.qml: FFStream client not initialized");
            if (onError) {
                onError("client not initialized");
            }
            return;
        }
        callback(ffstreamClient);
    }

    Connections {
        target: main.applicationWindow
        function onClosing(close) {
            close.accepted = false;
            main.locked = true;
        }
    }

    // Derive a default preview RTMP URL from the dx-producer host so
    // first-run users see a working preview without manual entry. Empty
    // dxProducerHost falls back to 127.0.0.1; a non-empty stored
    // previewRTMPUrl is never overwritten.
    function defaultPreviewRtmpUrl() {
        var addr = appSettings ? appSettings.dxProducerHost : "";
        var host = String(addr || "").replace(/^https?:\/\//, "").replace(/:[0-9]+\/?$/, "");
        if (host.length === 0) {
            host = "127.0.0.1";
        }
        return "rtmp://" + host + ":1945/pixel/dji-osmo-pocket-3-merged/";
    }

    Component.onCompleted: {
        console.log("Platform object type:", platform);
        if (platform && typeof platform.refreshWiFiState === 'function')
            platform.refreshWiFiState();
        if (appSettings && (!appSettings.previewRTMPUrl || appSettings.previewRTMPUrl.length === 0)) {
            appSettings.previewRTMPUrl = defaultPreviewRtmpUrl();
            console.log("Main.qml: seeded default previewRTMPUrl:", appSettings.previewRTMPUrl);
        }
    }

    StreamD.Client {
        id: dxProducerClient
        Component.onCompleted: {
            if (main.normalizedDxProducerHost && main.normalizedDxProducerHost.length > 0) {
                dxProducerClient.setServerUri(main.normalizedDxProducerHost);
                console.log("dxProducerClient setServerUri:", main.normalizedDxProducerHost);
            }
        }
    }

    Connections {
        target: main
        function onNormalizedDxProducerHostChanged() {
            if (main.normalizedDxProducerHost && main.normalizedDxProducerHost.length > 0) {
                dxProducerClient.setServerUri(main.normalizedDxProducerHost);
                console.log("dxProducerClient setServerUri:", main.normalizedDxProducerHost);
            }
        }
    }

    StackLayout {
        id: stack
        objectName: "stack"
        anchors.fill: parent
        currentIndex: 0

        Dashboard {
            id: dashboardPage
            root: main
        }
        Cameras {
            id: camerasPage
            root: main
        }
        DJIControl {
            id: djiControlPage
            root: main
            Component.onCompleted: console.log("DJIControl page completed")
        }
        Chat {
            id: chatPage
            root: main
        }
        Players {
            id: playersPage
            root: main
        }
        Restreams {
            id: restreamsPage
            root: main
        }
        Monitor {
            id: monitorPage
            root: main
        }
        Profiles {
            id: profilesPage
            root: main
        }
        Settings {
            id: settingsPage
            root: main
            appSettings: main.appSettings
        }
    }

    RoundButton {
        id: menuButton
        objectName: "menuButton"
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
        objectName: "lockButton"
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
