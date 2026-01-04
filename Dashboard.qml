import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Shapes
import QtGrpc
import Platform

import streamd as StreamD
import ffstream_grpc as FFStream

Page {
    id: dashboard
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Dashboard")

    property var latestChatMessageTimestampUNIXNano: null
    property var latestTimestampChatMessageIDs: []
    property var pingCurrentID: 0
    property var pingTimestamps: ({})
    property var pingInProgress: false
    readonly property bool isLandscape: width > height

    Component.onCompleted: {
        subscribeToChatMessages();
        pingTimestamps = {};
        ping();
        timers.pingTicker.callback = ping;
        timers.pingTicker.start();
        timers.streamStatusTicker.callback = updateStreamStatus;
        timers.streamStatusTicker.start();
        updateFFStreamLatencies();
        timers.updateFFStreamLatenciesTicker.callback = updateFFStreamLatencies;
        timers.updateFFStreamLatenciesTicker.start();
        updatePlayerLag();
        timers.updatePlayerLagTicker.callback = updatePlayerLag;
        timers.updatePlayerLagTicker.start();
        fetchPlayerLag();
        timers.fetchPlayerLagTicker.callback = fetchPlayerLag;
        timers.fetchPlayerLagTicker.start();
        updateFFStreamInputQuality();
        timers.updateFFStreamInputQualityTicker.callback = updateFFStreamInputQuality;
        timers.updateFFStreamInputQualityTicker.start();
        updateFFStreamOutputQuality();
        timers.updateFFStreamOutputQualityTicker.callback = updateFFStreamOutputQuality;
        timers.updateFFStreamOutputQualityTicker.start();
        updateFFStreamBitRates();
        timers.updateFFStreamBitRatesTicker.callback = updateFFStreamBitRates;
        timers.updateFFStreamBitRatesTicker.start();
        updateWiFiInfo();
        timers.updateWiFiInfoTicker.callback = updateWiFiInfo;
        timers.updateWiFiInfoTicker.start();
        updateChannelQualityInfo();
        timers.channelQualityInfoTicker.callback = updateChannelQualityInfo;
        timers.channelQualityInfoTicker.start();
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
        ffstreamClientGetLatencier.getLatencies(onGetLatenciesSuccess, onGetLatenciesError, grpcCallOptions);
    }

    function onGetLatenciesSuccess(latencies) {
        var audioLatencies = latencies.latencies.audio;
        var audioLatency = audioLatencies.preTranscodingU + audioLatencies.transcodingU + audioLatencies.transcodedPreSendU + audioLatencies.sendingU;
        var videoLatencies = latencies.latencies.video;
        var videoLatency = videoLatencies.preTranscodingU + videoLatencies.transcodingU + videoLatencies.transcodedPreSendU + videoLatencies.sendingU;
        var totalLatency = Math.max(audioLatency, videoLatency) / 1000000;
        sendingLatencyText.sendingLatency = totalLatency;
        //console.log("total latency:", totalLatency, "ms; audio: preTranscoding:", audioLatencies.preTranscodingU, "transcoding:", audioLatencies.transcodingU, "transcodedPreSend:", audioLatencies.transcodedPreSendU, "sending:", audioLatencies.sendingU, "total:", audioLatency, "; video: preTranscoding:", videoLatencies.preTranscodingU, "transcoding:", videoLatencies.transcodingU, "transcodedPreSend:", videoLatencies.transcodedPreSendU, "sending:", videoLatencies.sendingU, "total:", videoLatency, "; original:", JSON.stringify(latencies));
    }

    function onGetLatenciesError(error) {
        sendingLatencyText.sendingLatency = -1;
        processFFStreamGRPCError(ffstreamClientGetLatencier, error);
    }

    function updateFFStreamInputQuality() {
        ffstreamClientGetInputQualitier.getInputQuality(onGetInputQualitySuccess, onGetInputQualityError, grpcCallOptions);
    }

    function onGetInputQualitySuccess(inputQuality) {
        inputFPSText.inputFPS = inputQuality.video.frameRate;
        //console.log("input quality fps:", inputQuality.Video.frameRate);
    }

    function onGetInputQualityError(error) {
        inputFPSText.inputFPS = -1;
        processFFStreamGRPCError(ffstreamClientGetInputQualitier, error);
    }

    function updateFFStreamOutputQuality() {
        ffstreamClientGetOutputQualitier.getOutputQuality(onGetOutputQualitySuccess, onGetOutputQualityError, grpcCallOptions);
    }

    function onGetOutputQualitySuccess(outputQuality) {
        outputFPSText.outputFPS = outputQuality.video.frameRate;
        //console.log("output quality fps:", outputQuality.Video.frameRate);
    }

    function onGetOutputQualityError(error) {
        outputFPSText.outputFPS = -1;
        processFFStreamGRPCError(ffstreamClientGetOutputQualitier, error);
    }

    function updateFFStreamBitRates() {
        ffstreamClientGetBitRateser.getBitRates(onGetBitRatesSuccess, onGetBitRatesError, grpcCallOptions);
    }

    function onGetBitRatesSuccess(bitRates) {
        //console.log("bitRates:", bitRates.bitRates.outputBitRate);
        encodingBitrateText.videoBitrate = bitRates.bitRates.outputBitRate.video;
        //console.log("video bitrate:", bitRates.bitRates.outputBitRate.video);
    }

    function onGetBitRatesError(error) {
        encodingBitrateText.videoBitrate = -1;
        processFFStreamGRPCError(ffstreamClientGetBitRateser, error);
    }

    function updatePlayerLag() {
        if (playerLagText.playerLagMin <= 0) {
            return;
        }
        var now = new Date().getTime();
        var tsDiff = now - playerLagText.lastUpdateAt;
        //console.log("decreasing player lag min by ", tsDiff, "ms");
        playerLagText.playerLagMin -= tsDiff;
        if (playerLagText.playerLagMin < 0) {
            playerLagText.playerLagMin = 0;
        }
        playerLagText.lastUpdateAt = now;
    }

    function fetchPlayerLag() {
        dxProducerClientPlayerLagGetter.getPlayerLag(onGetPlayerLagSuccess, onGetPlayerLagError, grpcCallOptions);
    }

    function onGetPlayerLagSuccess(lagReply) {
        var now = new Date().getTime();
        var currentUnixNano = Math.floor(now * 1000000);
        var replyUnixNano = lagReply.replyUnixNano > lagReply.requestUnixNano ? lagReply.replyUnixNano : lagReply.requestUnixNano;
        var couldBeConsumedU = currentUnixNano - replyUnixNano;
        playerLagText.playerLagMin = (lagReply.lagU - couldBeConsumedU) / 1000000;
        playerLagText.playerLagMax = lagReply.lagU / 1000000;
        if (playerLagText.playerLagMin > playerLagText.playerLagMax) {
            playerLagText.playerLagMin = playerLagText.playerLagMax;
        }
        playerLagText.lastUpdateAt = now;
        //console.log("player lag min:", playerLagText.playerLagMin, "ms max:", playerLagText.playerLagMax, "ms couldBeConsumedU:", couldBeConsumedU, " replyUnixNano:", replyUnixNano, " currentUnixNano:", currentUnixNano);
    }

    function onGetPlayerLagError(error) {
        playerLagText.playerLagMin = -1;
        playerLagText.playerLagMax = -1;
        processStreamDGRPCError(dxProducerClientPinger, error);
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
            messageFormatType: messageFormatType
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
            updateStreamStatusYouTubeInProgress = true;
            dxProducerClientStreamStatusYouTube.getStreamStatus("youtube", false, onUpdateStreamStatusYouTube, onUpdateStreamStatusYouTubeError, grpcCallOptions);
        }
        if (!updateStreamStatusTwitchInProgress) {
            updateStreamStatusTwitchInProgress = true;
            dxProducerClientStreamStatusTwitch.getStreamStatus("twitch", false, onUpdateStreamStatusTwitch, onUpdateStreamStatusTwitchError, grpcCallOptions);
        }
        if (!updateStreamStatusKickInProgress) {
            updateStreamStatusKickInProgress = true;
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

    function updateWiFiInfo() {
        var wifiInfo = platform.getCurrentWiFiConnection();
        //console.log("WiFi info:", wifiInfo.toJSON());
        if (wifiInfo !== null && (wifiInfo.ssid !== "" || wifiInfo.bssid !== "")) {
            //console.log("updating WiFi status:", wifiInfo.ssid, wifiInfo.bssid, wifiInfo.rssi);
            wifiStatus.ssid = wifiInfo.ssid;
            wifiStatus.bssid = wifiInfo.bssid;
            wifiStatus.rssi = wifiInfo.rssi;
            return;
        }
        wifiStatus.ssid = "";
        wifiStatus.bssid = "";
        wifiStatus.rssi = -32768;
    }

    function updateChannelQualityInfo() {
        var channelsQualityInfo = platform.getChannelsQualityInfo();
        //console.log("channels quality info:", channelsQualityInfo, "; len:", channelsQualityInfo.length);
        for (var i = 0; i < channelsQualityInfo.length; i++) {
            var qualityInfo = channelsQualityInfo[i];
            //console.log(qualityInfo.toJSON());
            switch (i) {
            case 0:
                channel1Quality.quality = qualityInfo.quality;
                break;
            case 1:
                channel2Quality.quality = qualityInfo.quality;
                break;
            case 2:
                channel3Quality.quality = qualityInfo.quality;
                break;
            }
        }
    }

    Platform {
        id: platform
        Component.onCompleted: {
            platform.setEnableRunningInBackground(true);
            platform.startMonitoringSignalStrength();
            platform.startWiFiScan();
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
        id: dxProducerClientVideoRequester
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
    StreamD.Client {
        id: dxProducerClientPlayerLagGetter
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
        id: ffstreamClientGetLatencier
        channel: ffstreamTarget.channel
    }
    FFStream.Client {
        id: ffstreamClientGetInputQualitier
        channel: ffstreamTarget.channel
    }
    FFStream.Client {
        id: ffstreamClientGetOutputQualitier
        channel: ffstreamTarget.channel
    }
    FFStream.Client {
        id: ffstreamClientGetBitRateser
        channel: ffstreamTarget.channel
    }

    Row {
        id: statusBarTop
        x: 0
        y: 0
        width: parent.width
        height: dashboard.isLandscape ? 0 : 40
        spacing: 10
        visible: !dashboard.isLandscape

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

    function fpsColor(fps, thresholdBad, thresholdWarn, thresholdGood) {
        if (fps < thresholdBad) {
            return '#FF0000';
        }
        if (fps < thresholdWarn) {
            return colorMix('#FF0000', '#FFFF00', (fps - thresholdBad) / (thresholdWarn - thresholdBad));
        }
        if (fps < thresholdGood) {
            return colorMix('#FFFF00', '#00FF00', (fps - thresholdWarn) / (thresholdGood - thresholdWarn));
        }
        return '#00FF00';
    }

    function pingColorFromMS(durMS, thresholdWarn, thresholdBad) {
        if (durMS < 0) {
            return '#FF0000';
        }
        if (durMS < thresholdWarn) {
            return colorMix('#00FF00', '#FFFF00', durMS / thresholdWarn);
        }
        if (durMS < thresholdBad) {
            return colorMix('#FFFF00', '#FF0000', (durMS - thresholdWarn) / (thresholdBad - thresholdWarn));
        }
        return '#FF0000';
    }

    function pingColor2FromMS(durMS, lowBad, lowWarn, lowGood, highGood, highWarn, highBad) {
        if (durMS < lowBad) {
            return '#FF0000';
        }
        if (durMS < lowWarn) {
            return colorMix('#FF0000', '#FFFF00', (durMS - lowBad) / (lowWarn - lowBad));
        }
        if (durMS < lowGood) {
            return colorMix('#FFFF00', '#00FF00', (durMS - lowWarn) / (lowGood - lowWarn));
        }
        if (durMS < highGood) {
            return '#00FF00';
        }
        if (durMS < highWarn) {
            return colorMix('#00FF00', '#FFFF00', (durMS - highGood) / (highWarn - highGood));
        }
        if (durMS < highBad) {
            return colorMix('#FFFF00', '#FF0000', (durMS - highWarn) / (highBad - highWarn));
        }
        return '#FF0000';
    }

    function formatBandwidth(bw) {
        if (bw < 1000) {
            return bw + " bps";
        }
        var kbps = bw / 1000;
        if (kbps < 1000) {
            return kbps.toFixed(1) + " Kbps";
        }
        var mbps = kbps / 1000;
        if (mbps < 1000) {
            return mbps.toFixed(1) + " Mbps";
        }
        var gbps = mbps / 1000;
        return gbps.toFixed(1) + " Gbps";
    }

    function bwColor(bw, thresholdBad, thresholdWarn, thresholdGood) {
        if (bw < thresholdBad) {
            return '#FF0000';
        }
        if (bw < thresholdWarn) {
            return colorMix('#FF0000', '#FFFF00', (bw - thresholdBad) / (thresholdWarn - thresholdBad));
        }
        if (bw < thresholdGood) {
            return colorMix('#FFFF00', '#00FF00', (bw - thresholdWarn) / (thresholdGood - thresholdWarn));
        }
        return '#00FF00';
    }

    function formatDuration(durationMS) {
        if (durationMS < 200) {
            return durationMS + " ms";
        }
        var deciSeconds = Math.floor(durationMS / 100);
        var minutes = Math.floor(deciSeconds / 600);
        var seconds = Math.floor(deciSeconds / 10) % 60;
        if (minutes < 1) {
            deciSeconds -= seconds * 10;
            return seconds + "." + Math.floor(deciSeconds) + " s";
        }
        if (minutes < 60) {
            return minutes + " m " + seconds + " s";
        }
        var hours = Math.floor(minutes / 60);
        minutes = minutes % 60;
        return hours + " h " + minutes + " m " + seconds + " s";
    }

    function rssiColor(rssi) {
        if (rssi >= -50) {
            return '#00FF00';
        }
        if (rssi >= -60) {
            return colorMix('#FFFF00', '#00FF00', (-50 - rssi) / 10);
        }
        if (rssi >= -70) {
            return '#FFFF00';
        }
        if (rssi >= -80) {
            return colorMix('#FF0000', '#FFFF00', (-70 - rssi) / 10);
        }
        return '#FF0000';
    }

    function formatSSID(ssid, bssid) {
        console.log("formatSSID called with ssid:", ssid, " bssid:", bssid);
        switch (ssid) {
        case "home.dx.center":
        case "dslmodem.dx.center":
        case "slow.dslmodem.dx.center":
            switch ((bssid || "").toUpperCase()) {
            case "A8:29:48:3E:E2:F4":
                return "🏡◉";
            case "A8:29:48:3E:E7:A6":
                return "🏘◉";
            case "A8:29:48:3E:E3:B2":
                return "🏠◉";
            case "3C:A6:2F:15:B1:04":
                return "☎◉";
            default:
                return "?🏠◉";
            }
        case "":
            return "🚫";
        default:
            return "🛜◉";
        }
    }

    function channelQualityColor(quality) {
        if (quality < -33) {
            return '#FF0000';
        }
        if (quality < 0) {
            return colorMix('#FF0000', '#FFFF00', (quality + 33) / 33);
        }
        if (quality < 5) {
            return colorMix('#FFFF00', '#00FF00', quality / 5);
        }
        return '#00FF00';
    }

    VideoPlayerRTMP{
        id: imageScreenshot
        anchors.top: statusBarTop.bottom
        width: parent.width
        height: parent.width * 9 / 16
        source: sourcePreview
        property string sourcePreview: "rtmp://192.168.0.134:1935/preview/horizontal"
        property string sourceRawCamera: "rtmp://127.0.0.1:1935/proxy/dji-osmo-pocket3"

        Shape {
            id: overlayGrid

            anchors.fill: parent
            z: 1

            ShapePath {
                strokeWidth: 3
                strokeColor: '#80FFFFFF'
                fillColor: "transparent"

                startX: overlayGrid.width * 0.34179687499986157227
                startY: 0
                PathLine {
                    x: overlayGrid.width * 0.34179687499986157227
                    y: overlayGrid.height
                }
            }

            ShapePath {
                strokeWidth: 3
                strokeColor: '#80FFFFFF'
                fillColor: "transparent"
                startX: overlayGrid.width * 0.65820312500013842773
                startY: 0
                PathLine {
                    x: overlayGrid.width * 0.65820312500013842773
                    y: overlayGrid.height
                }
            }
        }

        ToolButton {
            id: videoSourceToggle
            anchors.margins: 12
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            font.pixelSize: 40
            checkable: true
            checked: false
            property real defaultOpacity: 0.6
            opacity: hovered ? 1.0 : defaultOpacity
            onToggled: function() {
                console.log("toggling video source to ", checked ? "raw" : "prod");
                imageScreenshot.source = videoSourceToggle.checked ? imageScreenshot.sourceRawCamera : imageScreenshot.sourcePreview;
            }
            text: checked ? "📷" : "🌐"
            ToolTip.visible: hovered
            ToolTip.text: checked ? "Switch to prod" : "Switch to raw"
        }
    }

    Page {
        id: statusBarBottom
        x: 0
        y: imageScreenshot.y + imageScreenshot.height
        width: parent.width
        height: 40

        Row {
            x: 0
            y: 0
            width: parent.width
            height: parent.height / 2
            spacing: 0

            Text {
                id: channel1Quality
                height: parent.height
                font.pixelSize: 20
                font.bold: true
                property int quality: -32768
                text: quality > -32768 ? "◉" : ""
                color: dashboard.channelQualityColor(quality)
            }
            Text {
                id: channel2Quality
                width: channel1Quality.width
                height: parent.height
                font.pixelSize: channel1Quality.font.pixelSize
                font.bold: true
                property int quality: -32768
                text: quality > -32768 ? "◉" : ""
                color: dashboard.channelQualityColor(quality)
            }
            Text {
                id: channel3Quality
                width: channel1Quality.width
                height: parent.height
                font.pixelSize: channel1Quality.font.pixelSize
                font.bold: true
                property int quality: -32768
                text: quality > -32768 ? "◉" : ""
                color: dashboard.channelQualityColor(quality)
            }

            Text {
                id: sendingLatencyText
                height: parent.height
                width: 100
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignRight
                property int sendingLatency: 0
                text: (sendingLatency < 0 ? "N/A" : dashboard.formatDuration(sendingLatency)) + "📱"
                color: dashboard.pingColorFromMS(sendingLatency, 680, 1500)
            }

            Text {
                id: pingStatus
                height: parent.height
                width: 100
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                property int rttMS: -1
                text: rttMS < 0 ? "no data" : "⇒" + dashboard.formatDuration(rttMS) + "⇒"
                color: dashboard.pingColorFromMS(rttMS, 100, 1000)

                Component.onCompleted: function () {
                    console.log("pingStatus: x,y,w,h: ", x, y, width, height);
                }
            }

            Text {
                id: playerLagText
                height: parent.height
                width: 120
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignLeft
                property int lastUpdateAt: -1
                property int playerLagMin: 0
                property int playerLagMax: 0
                //text: "💻" + (playerLagMin < 0 || playerLagMax < 0 ? "N/A" : application.formatDuration(playerLagMin) + " -- " + application.formatDuration(playerLagMax))
                text: "💻" + (playerLagMin < 0 || playerLagMax < 0 ? "N/A" : dashboard.formatDuration(playerLagMin))
                color: dashboard.pingColor2FromMS(playerLagMin, 300, 500, 1000, 5000, 10000, 60000)
            }

            Text {
                id: signalStatus
                height: parent.height
                width: 100
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                property int signalStrength: -1
                text: signalStrength < 0 ? "" : signalStrength
                color: '#FFFFFF'
            }
        }

        Row {
            x: 0
            y: parent.height / 2
            width: parent.width
            height: parent.height / 2
            spacing: 10

            Text {
                id: inputFPSText
                height: parent.height
                width: 100
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignLeft
                property int inputFPS: 0
                text: "in-FPS: " + (inputFPS < 0 ? "N/A" : inputFPS)
                color: dashboard.fpsColor(inputFPS, 15, 21, 24)
            }

            Text {
                id: outputFPSText
                height: parent.height
                width: 110
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignRight
                property int outputFPS: 0
                //text: "out-FPS: " + (outputFPS < 0 ? "N/A" : outputFPS)
                //color: application.fpsColor(outputFPS, 5, 10, 29)
                text: "out-FPS: ?"
                color: '#808080'
            }

            Text {
                id: encodingBitrateText
                height: parent.height
                width: 90
                font.pixelSize: 20
                font.bold: true
                property int videoBitrate: 0
                text: "enc: " + (videoBitrate < 0 ? "N/A" : dashboard.formatBandwidth(videoBitrate))
                color: dashboard.bwColor(videoBitrate, 50000, 1000000, 5000000)
                onVideoBitrateChanged: {
                    if (videoBitrate <= 0) {
                        return;
                    }
                    var isPreviewEnabled = imageScreenshot.source === imageScreenshot.sourcePreview;
                    var lowBitRateSource = "/tmp/low_bitrate.flv";
                    if (videoBitrate < 2000000) {
                        imageScreenshot.sourcePreview = lowBitRateSource;
                    } else {
                        imageScreenshot.sourcePreview = "rtmp://192.168.0.134:1935/preview/horizontal"
                    }
                    if (isPreviewEnabled) {
                        imageScreenshot.source = imageScreenshot.sourcePreview;
                    }
                }
            }

            Text {
                id: wifiStatus
                height: parent.height
                width: 100
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                property string ssid: ""
                property string bssid: ""
                property int rssi: -32768
                text: dashboard.formatSSID(ssid, bssid)
                color: dashboard.rssiColor(rssi)
            }
        }

        Component.onCompleted: function () {
            console.log("statusBarBottom: x,y,w,h: ", x, y, width, height);
        }
    }

    ChatView {
        id: chatView
        y: statusBarBottom.y + statusBarBottom.height
        width: parent.width
        height: parent.height - y
        Component.onCompleted: function () {
            console.log("ChatView: x,y,w,h: ", x, y, width, height);
        }
    }
}
