import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtGrpc
import Platform

import streamd

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out: Dashboard")

    property var latestChatMessageTimestampUNIXNano: null
    property var latestTimestampChatMessageIDs: []
    property var pingCurrentID: 0
    property var pingTimestamps: {}

    Component.onCompleted: {
        subscribeToChatMessages();
        subscribeToScreenshots();
        pingTimestamps = {};
        ping();
        timers.pingTicker.callback = ping;
        timers.pingTicker.start();
        timers.streamStatusTicker.callback = updateStreamStatus;
        timers.streamStatusTicker.start();
    }

    onClosing: {
        close.accepted = false;
        inputBlocker.visible = true;
    }

    MouseArea {
        id: inputBlocker
        anchors.fill: parent
        z: 9999
        visible: false
        enabled: true // Set to false to unlock
        opacity: 0.0
        property real startX: 0
        property real startY: 0
        onClicked: {}
        onPressed: {
            inputBlocker.startX = mouse.x;
            inputBlocker.startY = mouse.y;
        }
        onReleased: {
            var deltaY = mouse.y - inputBlocker.startY;
            var deltaX = mouse.x - inputBlocker.startX;
            if (deltaY >= -200) {
                return;
            }
            if (deltaX <= 200) {
                return;
            }
            inputBlocker.visible = false;
            platform.vibrate(50, false);
        }
    }

    function ping() {
        var now = new Date();
        var pingIDLastSuccess = pingCurrentID;
        var sinceLastSuccess = -1;
        for (var i = pingCurrentID - 1; i != pingCurrentID; i--) {
            if (i < 0) {
                i = 65535;
            }
            var byte0 = i / 0x100;
            var byte1 = i % 0x100;
            var payload = String.fromCharCode(byte0) + String.fromCharCode(byte1);
            var sentTimestamp = pingTimestamps[payload];
            if (sentTimestamp === undefined || sentTimestamp === null) {
                break;
            }
            sinceLastSuccess = now.getTime() - sentTimestamp.getTime();
            if (sinceLastSuccess > 10000) {
                pingStatus.rttMS = -1;
                sinceLastSuccess = -1;
                break;
            }
        }
        if (sinceLastSuccess > pingStatus.rttMS) {
            console.log("forcing displayed pingStatus.rttMS value to be ", sinceLastSuccess);
            pingStatus.rttMS = sinceLastSuccess;
        }
        var byte0 = pingCurrentID / 0x100;
        var byte1 = pingCurrentID % 0x100;
        pingCurrentID = (pingCurrentID + 1) % 65536;
        var payload = String.fromCharCode(byte0) + String.fromCharCode(byte1);
        pingTimestamps[payload] = new Date();
        dxProducerClient.ping(payload, "", 0, onPingSuccess, onPingFail, grpcCallOptions);
    }

    function subscribeToChatMessages() {
        var since = null;

        if (latestChatMessageTimestampUNIXNano == null) {
            since = new Date();
            since.setDate(since.getDate() - 7);
        } else {
            since = new Date(Math.floor(latestChatMessageTimestampUNIXNano / 1000000));
        }
        console.log("since: ", since);
        dxProducerClient.subscribeToChatMessages(since, 200, onChatNewMessage, onChatMessagesFinished, onChatMessagesErrored);
    }
    function subscribeToScreenshots() {
        dxProducerClient.subscribeToImage("screenshot", onNewScreenshot, onScreenshotFinished, onScreenshotErrored);
    }

    function onPingSuccess(reply): void {
        var receivedTimestamp = new Date();
        var sentTimestamp = pingTimestamps[reply.payload];
        if (sentTimestamp === undefined || sentTimestamp === null) {
            console.warn("timestamp found for payload:", reply.payload);
            return;
        }
        delete pingTimestamps[reply.payload];
        var timeDiffMs = receivedTimestamp.getTime() - sentTimestamp.getTime();
        pingStatus.rttMS = timeDiffMs;
    }

    function onPingFail(status): void {
        pingStatus.rttMS = -1;
    }

    function onChatNewMessage(chatMessage): void {
        if (latestChatMessageTimestampUNIXNano != null && latestChatMessageTimestampUNIXNano == chatMessage.createdAtUNIXNano) {
            var alreadyDisplayed = false;
            latestTimestampChatMessageIDs.foreach(function (item) {
                if (chatMessage) {
                    alreadyDisplayed = true;
                }
            });
            if (alreadyDisplayed) {
                console.log("message ", chatMessage.messageID, " is already displayed");
                return;
            }
        } else {
            latestTimestampChatMessageIDs.length = 0;
        }
        latestChatMessageTimestampUNIXNano = chatMessage.createdAtUNIXNano;
        latestTimestampChatMessageIDs.push(chatMessage.messageID);
        var item = {
            timestamp: String((new Date(Math.floor(chatMessage.createdAtUNIXNano / 1000000))).getMinutes()).padStart(2, "0"),
            isLive: chatMessage.isLive,
            platformName: chatMessage.platID,
            username: chatMessage.username,
            message: chatMessage.message
        };
        if (chatView.model.count > 200) {
            chatView.model.remove(0);
        }
        chatView.model.append(item);
    }
    function onChatMessagesFinished(status): void {
        console.log("Finished", status);
        timers.retryTimerDXProducerClientSubscribeToChatMessages.start();
    }

    function onChatMessagesErrored(status): void {
        console.log("Errored", status);
        timers.retryTimerDXProducerClientSubscribeToChatMessages.start();
    }

    function onNewScreenshot(screenshotURI): void {
        imageScreenshot.source = screenshotURI;
    }
    function onScreenshotFinished(status): void {
        console.log("Finished", status);
        timers.retryTimerDXProducerClientSubscribeToScreenshot.start();
    }
    function onScreenshotErrored(status): void {
        console.log("Errored", status);
        timers.retryTimerDXProducerClientSubscribeToScreenshot.start();
    }

    function updateStreamStatus() {
        dxProducerClient.getStreamStatus("youtube", false, onUpdateStreamStatusYouTube, onUpdateStreamStatusYouTubeError, grpcCallOptions);
        dxProducerClient.getStreamStatus("twitch", false, onUpdateStreamStatusTwitch, onUpdateStreamStatusTwitchError, grpcCallOptions);
        dxProducerClient.getStreamStatus("kick", false, onUpdateStreamStatusKick, onUpdateStreamStatusKickError, grpcCallOptions);
    }

    function onUpdateStreamStatusYouTube(streamStatus) {
        youtubeCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            youtubeCounter.value = streamStatus.viewersCount;
        } else {
            youtubeCounter.value = -1;
        }
        if (streamStatus.hasStartedAt) {
            var now = new Date();
            var seconds = now.getTime() - (streamStatus.startedAt / 1000000);
            statusStreamTime.seconds = seconds / 1000;
        } else {
            statusStreamTime.seconds = -1;
        }
    }
    function onUpdateStreamStatusYouTubeError() {
    }

    function onUpdateStreamStatusTwitch(streamStatus) {
        twitchCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            twitchCounter.value = streamStatus.viewersCount;
        } else {
            twitchCounter.value = -1;
        }
    }
    function onUpdateStreamStatusTwitchError() {
    }

    function onUpdateStreamStatusKick(streamStatus) {
        kickCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            kickCounter.value = streamStatus.viewersCount;
        } else {
            kickCounter.value = -1;
        }
    }
    function onUpdateStreamStatusKickError() {
    }

    Platform {
        id: platform
        Component.onCompleted: {
            platform.setEnableRunningInBackground(true);
            platform.startMonitoringSignalStrength();
        }
    }
    Connections {
        target: platform
        function onSignalStrengthChanged(strength) {
            console.log("new value of the signal strength: " + strength);
            signalStatus.signalStrength = strength;
        }
    }

    Timers {
        id: timers
        Component.onCompleted: {
            timers.retryTimerDXProducerClientSubscribeToChatMessages.callback = function () {
                console.log("re-subscribing to chat messages");
                subscribeToChatMessages();
            };
            timers.retryTimerDXProducerClientSubscribeToScreenshot.callback = function () {
                console.log("re-subscribing to the screenshots");
                subscribeToScreenshots();
            };
        }
    }
    GrpcCallOptions {
        id: grpcCallOptions
        deadlineTimeout: 1000
    }
    GrpcHttp2Channel {
        id: dxProducerTarget
        hostUri: "http://192.168.0.131:3594"
        options: GrpcChannelOptions {
            deadlineTimeout: 365 * 24 * 3600 * 1000
        }
    }
    Client {
        id: dxProducerClient
        channel: dxProducerTarget.channel
    }

    Image {
        id: screenshot
        x: 0
        y: 0
        width: parent.width
        height: parent.width * 9 / 16
    }

    Row {
        id: statusBarTop
        x: 0
        y: 0
        width: parent.width
        height: 40
        spacing: 10

        Text {
            id: youtubeCounter
            x: parent.spacing
            width: 60
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "Y " + value : "Y"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: twitchCounter
            width: 60
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "T " + value : "T"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: kickCounter
            width: 60
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "K " + value : "K"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: statusStreamTime
            font.pointSize: 20
            font.bold: true
            width: parent.width - kickCounter.x - kickCounter.width - parent.spacing * 2
            horizontalAlignment: Text.AlignRight
            color: seconds >= 0 ? '#00FF00' : '#808080'
            property int seconds: -1
            function pad(num) {
                return num < 10 ? "0" + num : num;
            }
            function formatTime(seconds) {
                if (seconds < 0)
                    return "not started";
                if (seconds < 60)
                    return pad(seconds);
                if (seconds < 3600)
                    return pad(Math.floor(seconds / 60)) + ":" + pad(seconds % 60);
                return Math.floor(seconds / 3600) + ":" + pad(Math.floor((seconds % 3600) / 60)) + ":" + pad(seconds % 60);
            }
            text: formatTime(seconds)
        }
    }

    function colorMix(colorA, colorB, ratio) {
        var cA = Qt.color(colorA);
        var cB = Qt.color(colorB);
        var r = cA.r * (1 - ratio) + cB.r * ratio;
        var g = cA.g * (1 - ratio) + cB.g * ratio;
        var b = cA.b * (1 - ratio) + cB.b * ratio;
        var a = cA.a * (1 - ratio) + cB.a * ratio;
        return Qt.rgba(r, g, b, a);
    }

    function pingColorFromMS(rttMS) {
        if (rttMS < 0) {
            return '#FF0000';
        }
        if (rttMS < 100) {
            return colorMix('#00FF00', '#FFFF00', rttMS / 100);
        }
        if (rttMS < 1000) {
            return colorMix('#FFFF00', '#FF0000', (rttMS - 100) / 900);
        }
        return '#FF0000';
    }

    Image {
        id: imageScreenshot
        y: statusBarTop.height
        width: parent.width
        height: parent.width * sourceSize.height / sourceSize.width
        fillMode: Image.PreserveAspectFit
        retainWhileLoading: true
        asynchronous: true
        smooth: false
    }

    ChatView {
        id: chatView
        y: imageScreenshot.y + imageScreenshot.height
        width: parent.width
        height: statusBarBottom.y - y

        onAtYEndChanged: function () {
            console.log("onAtYEndChanged", atYEnd);
            dxProducerClient.setIgnoreImages(!atYEnd);
        }
        Component.onCompleted: function () {
            console.log("ChatView: x,y,w,h: ", x, y, width, height);
        }
    }

    Row {
        id: statusBarBottom
        x: 20
        y: parent.height - 16
        width: parent.width - 40
        height: 16
        spacing: 10

        Text {
            id: pingStatus
            height: parent.height
            width: 100
            font.pixelSize: 12
            property int rttMS: -1
            text: rttMS < 0 ? "no data" : rttMS + "ms"
            color: application.pingColorFromMS(rttMS)

            Component.onCompleted: function () {
                console.log("pingStatus: x,y,w,h: ", x, y, width, height);
            }
        }

        Text {
            id: signalStatus
            height: parent.height
            width: 100
            font.pixelSize: 12
            property int signalStrength: -1
            text: signalStrength < 0 ? "" : signalStrength
            color: '#FFFFFF'
        }

        Component.onCompleted: function () {
            console.log("statusBarBottom: x,y,w,h: ", x, y, width, height);
        }
    }
}
