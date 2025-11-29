import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtGrpc
import Platform

import streamd as StreamD
import ffstream_grpc as FFStream

Page {
    id: application
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Dashboard")

    property var latestChatMessageTimestampUNIXNano: null
    property var latestTimestampChatMessageIDs: []
    property var pingCurrentID: 0
    property var pingTimestamps: {}
    property var pingInProgress: false

    Component.onCompleted: {
        subscribeToChatMessages();
        subscribeToScreenshots();
        pingTimestamps = {};
        ping();
        timers.pingTicker.callback = ping;
        timers.pingTicker.start();
        timers.streamStatusTicker.callback = updateStreamStatus;
        timers.streamStatusTicker.start();
        updateFFStreamLatencies();
        timers.updateFFStreamLatenciesTicker.callback = updateFFStreamLatencies;
        timers.updateFFStreamLatenciesTicker.start();
    }

    function ping() {
        var now = new Date();
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

        if (pingInProgress) {
            return;
        }
        pingInProgress = true;

        var byte0 = pingCurrentID / 0x100;
        var byte1 = pingCurrentID % 0x100;
        pingCurrentID = (pingCurrentID + 1) % 65536;
        var payload = String.fromCharCode(byte0) + String.fromCharCode(byte1);
        pingTimestamps[payload] = new Date();
        dxProducerClientPinger.ping(payload, "", 0, onPingSuccess, onPingFail, grpcCallOptions);
    }

    function updateFFStreamLatencies() {
        ffstreamClient.getLatencies(onGetLatenciesSuccess, onGetLatenciesError, grpcCallOptions);
    }

    function onGetLatenciesSuccess(latencies) {
        var audioLatencies = latencies.latencies.audio;
        var audioLatency = audioLatencies.preRecodingU + audioLatencies.recodingU + audioLatencies.recodedPreSendU + audioLatencies.sendingU;
        var videoLatencies = latencies.latencies.video;
        var videoLatency = videoLatencies.preRecodingU + videoLatencies.recodingU + videoLatencies.recodedPreSendU + videoLatencies.sendingU;
        var totalLatency = Math.max(audioLatency, videoLatency)/1000000;
        sendingLatencyText.sendingLatency = totalLatency;
        //console.log("total latency:", totalLatency,"ms ; latencies: audio:", audioLatencies, audioLatency, "; video:", videoLatencies, videoLatency);
    }

    function onGetLatenciesError(error) {
        sendingLatencyText.sendingLatency = -1;
        processFFStreamGRPCError(ffstreamClient, error);
    }

    function subscribeToChatMessages() {
        var since = null;

        if (latestChatMessageTimestampUNIXNano == null) {
            since = new Date();
            since.setDate(since.getDate() - 60);
        } else {
            since = new Date(Math.floor(latestChatMessageTimestampUNIXNano / 1000000));
        }
        console.log("since: ", since);
        dxProducerClientChatListener.subscribeToChatMessages(since, 200, onChatNewMessage, onChatMessagesFinished, onChatMessagesErrored);
    }
    function subscribeToScreenshots() {
        dxProducerClientScreenshotListener.subscribeToImage("screenshot", onNewScreenshot, onScreenshotFinished, onScreenshotErrored);
    }

    function onPingSuccess(reply): void {
        pingInProgress = false;
        var receivedTimestamp = new Date();
        var sentTimestamp = pingTimestamps[reply.payload];
        if (sentTimestamp === undefined || sentTimestamp === null) {
            console.warn("timestamp not found for payload:", reply.payload[0], reply.payload[1]);
            return;
        }
        delete pingTimestamps[reply.payload];
        var timeDiffMs = receivedTimestamp.getTime() - sentTimestamp.getTime();
        pingStatus.rttMS = timeDiffMs;
    }

    function onPingFail(error): void {
        pingInProgress = false;
        pingStatus.rttMS = -1;
        console.log("ping failed");
        processStreamDGRPCError(dxProducerClientPinger, error);
    }

    function onChatNewMessage(chatMessage): void {
        if (latestChatMessageTimestampUNIXNano != null && latestChatMessageTimestampUNIXNano == chatMessage.content.createdAtUNIXNano) {
            var alreadyDisplayed = false;
            latestTimestampChatMessageIDs.foreach(function (item) {
                if (chatMessage) {
                    alreadyDisplayed = true;
                }
            });
            if (alreadyDisplayed) {
                console.log("message ", chatMessage.content.ID, " is already displayed");
                return;
            }
        } else {
            latestTimestampChatMessageIDs.length = 0;
        }
        latestChatMessageTimestampUNIXNano = chatMessage.content.createdAtUNIXNano;
        latestTimestampChatMessageIDs.push(chatMessage.content.ID);

        var messageFormatType = 0;
        if (typeof chatMessage.content.message.formatType === "undefined" || chatMessage.content.message.formatType === null) {
            console.warn("message.formatType is undefined");
        } else {
            messageFormatType = chatMessage.content.message.formatType;
        }
        var usernameReadable = chatMessage.content.user.name;
        if (typeof chatMessage.content.user.nameReadable === "undefined" || chatMessage.content.user.nameReadable === null) {
            console.warn("user.nameReadable is undefined");
        } else {
            usernameReadable = chatMessage.content.user.nameReadable;
        }
        var item = {
            timestamp: String((new Date(Math.floor(chatMessage.content.createdAtUNIXNano / 1000000))).getMinutes()).padStart(2, "0"),
            isLive: chatMessage.isLive,
            eventType: chatMessage.content.eventType,
            platformName: chatMessage.platID,
            username: chatMessage.content.user.name,
            usernameReadable: chatMessage.content.user.nameReadable,
            message: chatMessage.content.message.content,
            messageFormatType: messageFormatType,
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

    function onChatMessagesErrored(error): void {
        console.log("Errored", error);
        processStreamDGRPCError(dxProducerClientChatListener, error);
        timers.retryTimerDXProducerClientSubscribeToChatMessages.start();
    }

    function onNewScreenshot(screenshotURI): void {
        imageScreenshot.source = screenshotURI;
    }
    function onScreenshotFinished(status): void {
        console.log("Finished", status);
        timers.retryTimerDXProducerClientSubscribeToScreenshot.start();
    }
    function onScreenshotErrored(error): void {
        console.log("Errored", error);
        processStreamDGRPCError(dxProducerClientScreenshotListener, error);
        timers.retryTimerDXProducerClientSubscribeToScreenshot.start();
    }

    function processStreamDGRPCError(dxProducer, error): void {
        dxProducer.processGRPCError(error);
    }

    function processFFStreamGRPCError(ffstream, error): void {
        ffstream.processGRPCError(error);
    }

    property var updateStreamStatusYouTubeInProgress: false
    property var updateStreamStatusTwitchInProgress: false
    property var updateStreamStatusKickInProgress: false

    function updateStreamStatus() {
        if (!updateStreamStatusYouTubeInProgress) {
            updateStreamStatusYouTubeInProgress = true
            dxProducerClientStreamStatusYouTube.getStreamStatus("youtube", false, onUpdateStreamStatusYouTube, onUpdateStreamStatusYouTubeError, grpcCallOptions);
        }
        if (!updateStreamStatusTwitchInProgress) {
            updateStreamStatusTwitchInProgress = true
            dxProducerClientStreamStatusTwitch.getStreamStatus("twitch", false, onUpdateStreamStatusTwitch, onUpdateStreamStatusTwitchError, grpcCallOptions);
        }
        if (!updateStreamStatusKickInProgress) {
            updateStreamStatusKickInProgress = true
            dxProducerClientStreamStatusKick.getStreamStatus("kick", false, onUpdateStreamStatusKick, onUpdateStreamStatusKickError, grpcCallOptions);
        }
    }

    function onUpdateStreamStatusYouTube(streamStatus) {
        updateStreamStatusYouTubeInProgress = false;
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
    function onUpdateStreamStatusYouTubeError(error) {
        updateStreamStatusYouTubeInProgress = false;
        processStreamDGRPCError(dxProducerClientStreamStatusYouTube, error);
    }

    function onUpdateStreamStatusTwitch(streamStatus) {
        updateStreamStatusTwitchInProgress = false;
        twitchCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            twitchCounter.value = streamStatus.viewersCount;
        } else {
            twitchCounter.value = -1;
        }
    }
    function onUpdateStreamStatusTwitchError(error) {
        updateStreamStatusTwitchInProgress = false;
        processStreamDGRPCError(dxProducerClientStreamStatusTwitch, error);
    }

    function onUpdateStreamStatusKick(streamStatus) {
        updateStreamStatusKickInProgress = false;
        kickCounter.isActive = streamStatus.isActive;
        if (streamStatus.hasViewersCount) {
            kickCounter.value = streamStatus.viewersCount;
        } else {
            kickCounter.value = -1;
        }
    }
    function onUpdateStreamStatusKickError(error) {
        updateStreamStatusKickInProgress = false;
        processStreamDGRPCError(dxProducerClientStreamStatusTwitch, error);
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
        deadlineTimeout: 10000
    }
    GrpcHttp2Channel {
        id: dxProducerTarget
        hostUri: "https://192.168.0.134:3594"
        options: GrpcChannelOptions {
            deadlineTimeout: 365 * 24 * 3600 * 1000
        }
    }
    StreamD.Client {
        id: dxProducerClientPinger
        channel: dxProducerTarget.channel
    }
    StreamD.Client {
        id: dxProducerClientChatListener
        channel: dxProducerTarget.channel
    }
    StreamD.Client {
        id: dxProducerClientScreenshotListener
        channel: dxProducerTarget.channel
    }
    StreamD.Client {
        id: dxProducerClientStreamStatusYouTube
        channel: dxProducerTarget.channel
    }
    StreamD.Client {
        id: dxProducerClientStreamStatusTwitch
        channel: dxProducerTarget.channel
    }
    StreamD.Client {
        id: dxProducerClientStreamStatusKick
        channel: dxProducerTarget.channel
    }
    GrpcHttp2Channel {
        id: ffstreamTarget
        hostUri: "https://127.0.0.1:3593"
        options: GrpcChannelOptions {
            deadlineTimeout: 365 * 24 * 3600 * 1000
        }
    }
    FFStream.Client {
        id: ffstreamClient
        channel: ffstreamTarget.channel
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

    function pingColorFromMS(rttMS, thresholdWarn, thresholdBad) {
        if (rttMS < 0) {
            return '#FF0000';
        }
        if (rttMS < thresholdWarn) {
            return colorMix('#00FF00', '#FFFF00', rttMS / thresholdWarn);
        }
        if (rttMS < thresholdBad) {
            return colorMix('#FFFF00', '#FF0000', (rttMS-thresholdWarn) / (thresholdBad-thresholdWarn));
        }
        return '#FF0000';
    }

    function formatDuration(durationMS) {
        if (durationMS < 1000) {
            return durationMS + " ms";
        }
        var deciSeconds = Math.floor(durationMS / 100);
        var minutes = Math.floor(deciSeconds / 600);
        var seconds = Math.floor(deciSeconds / 10) % 60;
        if (minutes < 1) {
            deciSeconds -= seconds * 10;
            return seconds+"."+Math.floor(deciSeconds)+" s";
        }
        if (minutes < 60) {
            return minutes + " m " + seconds + " s";
        }
        var hours = Math.floor(minutes / 60);
        minutes = minutes % 60;
        return hours + " h " + minutes + " m " + seconds + " s";
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
            dxProducerClientScreenshotListener.setIgnoreImages(!atYEnd);
        }
        Component.onCompleted: function () {
            console.log("ChatView: x,y,w,h: ", x, y, width, height);
        }
    }

    Row {
        id: statusBarBottom
        x: 30
        y: parent.height - 30
        width: parent.width - 40
        height: 20
        spacing: 10

        Text {
            id: pingStatus
            height: parent.height
            width: 100
            font.pixelSize: 24
            font.bold: true
            property int rttMS: -1
            text: rttMS < 0 ? "no data" : application.formatDuration(rttMS)
            color: application.pingColorFromMS(rttMS, 100, 1000)

            Component.onCompleted: function () {
                console.log("pingStatus: x,y,w,h: ", x, y, width, height);
            }
        }

        Text {
            id: signalStatus
            height: parent.height
            width: 100
            font.pixelSize: 24
            font.bold: true
            property int signalStrength: -1
            text: signalStrength < 0 ? "" : signalStrength
            color: '#FFFFFF'
        }

        Text {
            id: sendingLatencyText
            height: parent.height
            width: 100
            font.pixelSize: 24
            font.bold: true
            property int sendingLatency: 0
            text: sendingLatency < 0 ? "N/A" : application.formatDuration(sendingLatency)
            color: application.pingColorFromMS(sendingLatency, 680, 1500)
        }

        Component.onCompleted: function () {
            console.log("statusBarBottom: x,y,w,h: ", x, y, width, height);
        }
    }
}
