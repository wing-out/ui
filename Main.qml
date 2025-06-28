import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtGrpc

import streamd

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Backstage: dashboard")

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
        handleDXProducerClientStatus(QtGrpc.StatusCode.Ok);
    }

    function ping() {
        var byte0 = pingCurrentID / 0x100;
        var byte1 = pingCurrentID % 0x100;
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
        var timeDiffMs = receivedTimestamp.getTime() - sentTimestamp.getTime();

        statusBarBottom.text = timeDiffMs + "ms";
        statusBarBottom.color = "#4CAF50";
    }

    function onPingFail(status): void {
        handleDXProducerClientStatus(status);
    }

    function onChatNewMessage(chatMessage): void {
        //console.log("onChatNewMessage", chatMessage)
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
    }
    function onScreenshotErrored(status): void {
        console.log("Errored", status);
        timers.retryTimerDXProducerClientSubscribeToScreenshot.start();
    }

    function handleDXProducerClientStatus(status): void {
        switch (status.code) {
        case QtGrpc.StatusCode.Ok:
            statusBarBottom.text = qsTr("ok");
            statusBarBottom.color = "#4CAF50";
            break;
        case QtGrpc.StatusCode.Unavailable:
            statusBarBottom.text = qsTr("no connection");
            statusBarBottom.color = "#F44336";
            break;
        default:
            statusBarBottom.text = qsTr("unknown");
            statusBarBottom.color = "#F44336";
            break;
        }
    }

    function updateStreamStatus() {
        dxProducerClient.getStreamStatus("youtube", onUpdateStreamStatusYouTube, onUpdateStreamStatusYouTubeError, grpcCallOptions);
        dxProducerClient.getStreamStatus("twitch", onUpdateStreamStatusTwitch, onUpdateStreamStatusTwitchError, grpcCallOptions);
        dxProducerClient.getStreamStatus("kick", onUpdateStreamStatusKick, onUpdateStreamStatusKickError, grpcCallOptions);
    }

    function onUpdateStreamStatusYouTube(streamStatus) {
        youtubeCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            youtubeCounter.value = streamStatus.viewerCount;
        } else {
            youtubeCounter.value = -1;
        }
        if (streamStatus.hasStartedAt) {
            var now = new Date();
            var seconds = now.getTime() - (streamStatus.startedAt / 1000000);
            statusStreamTime.seconds = seconds;
        } else {
            statusStreamTime.seconds = -1;
        }
    }
    function onUpdateStreamStatusYouTubeError() {
    }

    function onUpdateStreamStatusTwitch(streamStatus) {
        twitchCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            twitchCounter.value = streamStatus.viewerCount;
        } else {
            twitchCounter.value = -1;
        }
    }
    function onUpdateStreamStatusTwitchError() {
    }

    function onUpdateStreamStatusKick(streamStatus) {
        kickCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            kickCounter.value = streamStatus.viewerCount;
        } else {
            kickCounter.value = -1;
        }
    }
    function onUpdateStreamStatusKickError() {
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
        hostUri: "http://192.168.0.134:3594"
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
            width: 60;
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "Y" + value : "Y"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: twitchCounter
            width: 60;
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "T" + value : "T"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: kickCounter
            width: 60;
            color: isActive ? '#00FF00' : '#808080'
            text: value >= 0 ? "K" + value : "K"
            font.pointSize: 20
            font.bold: true
            property int value: -1
            property bool isActive: false
        }
        Text {
            id: statusStreamTime
            font.pointSize: 20
            font.bold: true
            width: parent.width - kickCounter.x - kickCounter.width - parent.spacing*2
            horizontalAlignment: Text.AlignRight
            color: seconds >= 0 ? '#00FF00' : '#808080'
            property int seconds: -1
            text: seconds < 0 ? "not started" : (seconds < 60 ? seconds : (seconds < 3600 ? Math.floor(seconds / 60)+":"+(seconds % 60) : Math.floor(seconds / 3600)+":"+Math.floor(seconds % 3600 / 60)+":"+(seconds % 60)))
        }
    }

    Text {
        id: statusBarBottom
        x: 20
        y: parent.height - 16
        width: parent.width - 40
        height: 16
        text: qsTr("")
        font.pixelSize: 12
    }

    ChatView {
        id: chatView
        y: imageScreenshot.y + imageScreenshot.height
        width: parent.width
        height: parent.height - statusBarBottom.height - imageScreenshot.height

        onAtYEndChanged: function () {
            console.log("onAtYEndChanged", atYEnd);
            dxProducerClient.setIgnoreImages(!atYEnd);
        }
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
}
