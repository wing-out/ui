pragma ComponentBehavior: Bound
/* This file implements the main dashboard with chat, monitor data, and various stream status indicators. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Shapes
import QtCore as Core

Page {
    id: dashboard
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Dashboard")

    required property var root
    property var latestChatMessageTimestampUNIXNano: null
    property var pingCurrentID: 0
    property var pingTimestamps: ({})
    property var pingInProgress: false
    // Auto-picked streamID (first enabled player from listStreamPlayers).
    // Populated lazily — refreshChosenPlayerStreamID is called from
    // fetchPlayerLag when the channel is finally ready.
    property string autoChosenPlayerStreamID: ""
    // Effective streamID: user override from settings if set, else auto-picked.
    readonly property string chosenPlayerStreamID:
        (dashboard.root && dashboard.root.appSettings
            && dashboard.root.appSettings.chosenPlayerStreamID
            && dashboard.root.appSettings.chosenPlayerStreamID.length > 0)
            ? dashboard.root.appSettings.chosenPlayerStreamID
            : autoChosenPlayerStreamID
    // Guard so refreshChosenPlayerStreamID does not spam-retry.
    property bool _refreshChosenPlayerStreamIDInProgress: false
    readonly property bool isLandscape: width > height
    property var lastDiagnostics: ({})
    property int diagnosticsUpdateCount: 0
    property var platformCapabilities: ({})
    property int lastFPSLogAt: 0
    
    // For calculating FPS from stats
    property var lastStatsFrameCount: 0
    property var lastStatsTimestamp: 0
    property real calculatedInputFPS: -1

    // Uses "dashboard" category so this Settings writes to
    // [dashboard] section, not [General]. Application.qml has
    // its own Settings for dxProducerHost under [General] — two
    // Settings in the same section cause the last sync to
    // overwrite the other's keys.
    // Use qualified import to avoid shadowing by local Settings.qml
    // (which is a Page component for the config editor, not QSettings).
    Core.Settings {
        id: appSettings
        category: "dashboard"
        property bool soundEnabled: true
    }

    Timers {
        id: timers
    }

    Component.onCompleted: {
        subscribeToChatMessages();
        fetchPlatformCapabilities();
        refreshChosenPlayerStreamID();
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
        updateFFStreamFPSFraction();
        timers.updateFFStreamFPSFractionTicker.callback = updateFFStreamFPSFraction;
        timers.updateFFStreamFPSFractionTicker.start();
        updateFFStreamOutputQuality();
        timers.updateFFStreamOutputQualityTicker.callback = updateFFStreamOutputQuality;
        timers.updateFFStreamOutputQualityTicker.start();
        updateFFStreamBitRates();
        timers.updateFFStreamBitRatesTicker.callback = updateFFStreamBitRates;
        timers.updateFFStreamBitRatesTicker.start();
        updateWiFiInfo();
        timers.updateWiFiInfoTicker.callback = updateWiFiInfo;
        timers.updateWiFiInfoTicker.start();
        timers.updateResourcesTicker.callback = function () {
            dashboard.root.platform.updateResources();
        };
        timers.updateResourcesTicker.start();
        updateChannelQualityInfo();
        timers.channelQualityInfoTicker.callback = updateChannelQualityInfo;
        timers.channelQualityInfoTicker.start();
        timers.injectDiagnosticsSubtitlesTicker.callback = injectDiagnosticsSubtitles;
        timers.injectDiagnosticsSubtitlesTicker.start();
        timers.retryTimerSubscribeToChatMessages.callback = function () {
            console.log("re-subscribing to chat messages");
            subscribeToChatMessages();
        };
    }

    function normalizeNumber(value) {
        if (value === undefined || value === null) {
            return null;
        }
        var num = Number(value);
        if (!isFinite(num)) {
            return null;
        }
        return num;
    }

    function normalizeLatencyU(value) {
        var num = normalizeNumber(value);
        if (num === null || num < 0 || num > 1e12) {
            return null;
        }
        return num;
    }

    function sumLatencyParts(track) {
        if (!track) {
            return null;
        }
        var parts = [track.preTranscodingU, track.transcodingU, track.transcodedPreSendU];
        var sum = 0;
        var hasAny = false;
        for (var i = 0; i < parts.length; i++) {
            var part = normalizeLatencyU(parts[i]);
            if (part !== null) {
                sum += part;
                hasAny = true;
            }
        }
        return hasAny ? sum : null;
    }

    function maxValidNumber(a, b) {
        if (a === null && b === null) {
            return null;
        }
        if (a === null) {
            return b;
        }
        if (b === null) {
            return a;
        }
        return Math.max(a, b);
    }

    function normalizeFPS(value) {
        var num = normalizeNumber(value);
        if (num === null || num <= 0) {
            return null;
        }
        return num;
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

        dashboard.root.withStreamClient(function(client) {
            client.ping(payload, "", 0, onPingSuccess, onPingFail, dashboard.root.grpcCallOptions);
        }, function(error) {
            pingInProgress = false;
            onPingFail(error);
        }, "Dashboard.ping");
    }

    function updateFFStreamLatencies() {
        if (!dashboard.root.checkFFStreamClient()) {
            return;
        }
        dashboard.root.ffstreamClient.getLatencies(onGetLatenciesSuccess, onGetLatenciesError, dashboard.root.grpcCallOptions);
    }

    function onGetLatenciesSuccess(latencies) {
        console.log("Dashboard.qml: Received latencies: " + JSON.stringify(latencies));
        if (!latencies || !latencies.latencies) {
            sendingLatencyText.preSendingLatency = -1;
            sendingLatencyText.sendingLatency = -1;
            return;
        }
        var audioLatencies = latencies.latencies.audio;
        var videoLatencies = latencies.latencies.video;
        var audioPreSending = sumLatencyParts(audioLatencies);
        var videoPreSending = sumLatencyParts(videoLatencies);
        var audioSending = normalizeLatencyU(audioLatencies ? audioLatencies.sendingU : null);
        var videoSending = normalizeLatencyU(videoLatencies ? videoLatencies.sendingU : null);

        var preSendingU = maxValidNumber(audioPreSending, videoPreSending);
        var sendingU = maxValidNumber(audioSending, videoSending);

        if (preSendingU === null && sendingU === null) {
            sendingLatencyText.preSendingLatency = -1;
            sendingLatencyText.sendingLatency = -1;
            return;
        }

        var preSendingLatency = preSendingU !== null ? preSendingU / 1000000 : 0;
        var sendingLatency = sendingU !== null ? sendingU / 1000000 : 0;

        sendingLatencyText.preSendingLatency = preSendingLatency;
        sendingLatencyText.sendingLatency = sendingLatency;
        //console.log("latencies: audio: preSending:", audioPreSending, "sending:", audioSending, "; video: preSending:", videoPreSending, "sending:", videoSending, "; original:", JSON.stringify(latencies));
    }

    function onGetLatenciesError(error) {
        sendingLatencyText.preSendingLatency = -1;
        sendingLatencyText.sendingLatency = -1;
        dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
    }

    function updateFFStreamInputQuality() {
        console.log("Dashboard.qml: updateFFStreamInputQuality called");
        if (!dashboard.root.checkFFStreamClient()) {
            console.log("Dashboard.qml: updateFFStreamInputQuality - ffstream client not available");
            return;
        }
        dashboard.root.ffstreamClient.getInputQuality(onGetInputQualitySuccess, onGetInputQualityError, dashboard.root.grpcCallOptions);
    }

    function onGetInputQualitySuccess(inputQuality) {
        var fps = null;
        if (inputQuality && inputQuality.video) {
            fps = normalizeFPS(inputQuality.video.frameRate);
        }
        inputFPSText.inputFPS = fps !== null ? fps : -1;
    }

    function onGetInputQualityError(error) {
        inputFPSText.inputFPS = -1;
        dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
    }

    function updateFFStreamFPSFraction() {
        if (!dashboard.root.checkFFStreamClient()) {
            return;
        }
        dashboard.root.ffstreamClient.getFPSFraction(onGetFPSFractionSuccess, onGetFPSFractionError, dashboard.root.grpcCallOptions);
    }

    function onGetFPSFractionSuccess(reply) {
        if (!reply) {
            return;
        }
        var num = normalizeNumber(reply.num);
        var den = normalizeNumber(reply.den);
        if (num === null || den === null || den <= 0) {
            return;
        }
        var fps = num / den;
        if (isFinite(fps) && fps > 0 && inputFPSText.inputFPS < 0) {
            inputFPSText.inputFPS = fps;
        }
    }

    function onGetFPSFractionError(error) {
        dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
    }

    function updateFFStreamOutputQuality() {
        if (!dashboard.root.checkFFStreamClient()) {
            return;
        }
        dashboard.root.ffstreamClient.getOutputQuality(onGetOutputQualitySuccess, onGetOutputQualityError, dashboard.root.grpcCallOptions);
    }

    function onGetOutputQualitySuccess(outputQuality) {
        var fps = null;
        if (outputQuality && outputQuality.video) {
            fps = normalizeFPS(outputQuality.video.frameRate);
        }
        outputFPSText.outputFPS = fps !== null ? fps : -1;
    }

    function onGetOutputQualityError(error) {
        outputFPSText.outputFPS = -1;
        dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
    }

    function updateFFStreamBitRates() {
        if (!dashboard.root.checkFFStreamClient()) {
            return;
        }
        dashboard.root.ffstreamClient.getBitRates(onGetBitRatesSuccess, onGetBitRatesError, dashboard.root.grpcCallOptions);
    }

    function onGetBitRatesSuccess(bitRates) {
        console.log("Dashboard.qml: Received bitRates: " + JSON.stringify(bitRates));
        if (!bitRates || !bitRates.bitRates || !bitRates.bitRates.outputBitRate) {
            encodingBitrateText.videoBitrate = -1;
            return;
        }
        var video = normalizeNumber(bitRates.bitRates.outputBitRate.video);
        if (video === null || video <= 0) {
            encodingBitrateText.videoBitrate = -1;
            return;
        }
        encodingBitrateText.videoBitrate = video;
        //console.log("video bitrate:", bitRates.bitRates.outputBitRate.video);
    }

    function onGetBitRatesError(error) {
        encodingBitrateText.videoBitrate = -1;
        dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
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

    function refreshChosenPlayerStreamID() {
        if (dashboard._refreshChosenPlayerStreamIDInProgress) {
            return;
        }
        if (!dashboard.root.checkStreamDClient()) {
            return;
        }
        // checkStreamDClient is a null-check only. Skip the call before
        // the gRPC channel is ready — it would be silently dropped and
        // neither callback would ever fire, leaving _refresh...InProgress
        // stuck true forever.
        if (!dashboard.root.dxProducerClient.isChannelReady()) {
            return;
        }
        dashboard._refreshChosenPlayerStreamIDInProgress = true;
        dashboard.root.dxProducerClient.listStreamPlayers(function (reply) {
            dashboard._refreshChosenPlayerStreamIDInProgress = false;
            var players = reply.playersData || reply.players || [];
            console.log("Dashboard.qml: listStreamPlayers returned", players.length, "players");
            for (var i = 0; i < players.length; i++) {
                var p = players[i];
                if (p.disabled === true) {
                    continue;
                }
                if (!p.streamID) {
                    continue;
                }
                console.log("Dashboard.qml: autoChosenPlayerStreamID =", p.streamID);
                dashboard.autoChosenPlayerStreamID = p.streamID;
                return;
            }
            console.log("Dashboard.qml: no enabled player found in listStreamPlayers");
        }, function (error) {
            dashboard._refreshChosenPlayerStreamIDInProgress = false;
            console.log("Dashboard.qml: listStreamPlayers failed");
            dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
        }, dashboard.root.grpcCallOptions);
    }

    function fetchPlayerLag() {
        if (!dashboard.root.checkStreamDClient()) {
            return;
        }
        if (!dashboard.chosenPlayerStreamID) {
            // No streamID resolved yet. If there is also no auto-picked
            // value, retry listStreamPlayers — earlier calls may have
            // fired before the gRPC channel became ready and were
            // silently dropped. Skip getPlayerLag to avoid hammering
            // the server with blank streamIDs.
            if (!dashboard.autoChosenPlayerStreamID) {
                refreshChosenPlayerStreamID();
            }
            return;
        }
        dashboard.root.dxProducerClient.getPlayerLag(dashboard.chosenPlayerStreamID, onGetPlayerLagSuccess, onGetPlayerLagError, dashboard.root.grpcCallOptions);
    }

    function onGetPlayerLagSuccess(lagReply) {
        console.log("Dashboard.qml: Received player lag reply");
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
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
    }

    function subscribeToChatMessages() {
        if (!dashboard.root.checkStreamDClient()) {
            return;
        }
        var since = null;

        if (latestChatMessageTimestampUNIXNano == null) {
            since = new Date();
            since.setDate(since.getDate() - 60);
        } else {
            since = new Date(Math.floor(latestChatMessageTimestampUNIXNano / 1000000));
        }
        console.log("since: ", since);

        dashboard.root.dxProducerClient.subscribeToChatMessages(since, 200, onChatNewMessage, onChatMessagesFinished, onChatMessagesErrored, dashboard.root.streamingGrpcCallOptions);
    }

    function onPingSuccess(reply): void {
        console.log("Dashboard.qml: Received ping reply");
        pingInProgress = false;
        var receivedTimestamp = new Date();
        var sentTimestamp = pingTimestamps[reply.payload];
        if (sentTimestamp === undefined || sentTimestamp === null) {
            console.warn("timestamp not found for payload:", reply.payload);
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
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
    }

    function onChatNewMessage(chatMessage): void {
        console.log("Dashboard.qml: Received new chat message");
        var eventID = chatMessage.content.id_proto;

        // Dedup: check if eventID already exists in model
        for (var i = 0; i < chatView.model.count; i++) {
            if (chatView.model.get(i).eventID === eventID) {
                console.log("message ", eventID, " is already displayed");
                return;
            }
        }

        // Message is optional in the proto — events like subscriptions,
        // bans, raids, and "said hi" notifications have no message body.
        var hasMessage = chatMessage.content.message !== null
            && typeof chatMessage.content.message !== "undefined";
        var messageFormatType = 0;
        var messageContent = "";
        if (hasMessage) {
            if (typeof chatMessage.content.message.formatType !== "undefined"
                    && chatMessage.content.message.formatType !== null) {
                messageFormatType = chatMessage.content.message.formatType;
            }
            messageContent = chatMessage.content.message.content || "";
        }
        var moneyAmount = 0;
        var moneyCurrency = 0;
        if (chatMessage.content.hasMoney) {
            moneyAmount = chatMessage.content.money.amount;
            moneyCurrency = chatMessage.content.money.currency;
        }
        var item = {
            timestamp: String((new Date(Math.floor(chatMessage.content.createdAtUNIXNano / 1000000))).getMinutes()).padStart(2, "0"),
            isLive: chatMessage.isLive,
            eventType: chatMessage.content.eventType,
            platformName: chatMessage.platID,
            username: chatMessage.content.user.name,
            usernameReadable: chatMessage.content.user.nameReadable,
            message: messageContent,
            messageFormatType: messageFormatType,
            isTest: false,
            eventID: eventID,
            userID: chatMessage.content.user.id_proto,
            moneyAmount: moneyAmount,
            moneyCurrency: moneyCurrency
        };
        latestChatMessageTimestampUNIXNano = chatMessage.content.createdAtUNIXNano;
        if (chatView.model.count > 200) {
            chatView.model.remove(0);
        }
        chatView.model.append(item);
    }
    function onChatMessagesFinished(status): void {
        console.log("Finished", status);
        timers.retryTimerSubscribeToChatMessages.start();
    }

    function onChatMessagesErrored(error): void {
        console.log("Errored", error);
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
        timers.retryTimerSubscribeToChatMessages.start();
    }

    function fetchPlatformCapabilities() {
        var platforms = ["twitch", "youtube", "kick"];
        for (var i = 0; i < platforms.length; i++) {
            (function(platID) {
                dxProducerClient.getBackendInfo(platID, function(reply) {
                    var caps = platformCapabilities;
                    caps[platID] = reply.capabilities;
                    platformCapabilities = caps;
                    chatView.platformCapabilities = platformCapabilities;
                }, function(error) {
                    console.warn("getBackendInfo failed for", platID, error);
                }, grpcCallOptions);
            })(platforms[i]);
        }
    }

    property var updateStreamStatusYouTubeInProgress: false
    property var updateStreamStatusTwitchInProgress: false
    property var updateStreamStatusKickInProgress: false

    function updateStreamStatus() {
        if (!dashboard.root.checkStreamDClient()) {
            return;
        }
        if (!updateStreamStatusYouTubeInProgress) {
            updateStreamStatusYouTubeInProgress = true;
            dashboard.root.dxProducerClient.getStreamStatus("youtube", false, onUpdateStreamStatusYouTube, onUpdateStreamStatusYouTubeError, dashboard.root.grpcCallOptions);
        }
        if (!updateStreamStatusTwitchInProgress) {
            updateStreamStatusTwitchInProgress = true;
            dashboard.root.dxProducerClient.getStreamStatus("twitch", false, onUpdateStreamStatusTwitch, onUpdateStreamStatusTwitchError, dashboard.root.grpcCallOptions);
        }
        if (!updateStreamStatusKickInProgress) {
            updateStreamStatusKickInProgress = true;
            dashboard.root.dxProducerClient.getStreamStatus("kick", false, onUpdateStreamStatusKick, onUpdateStreamStatusKickError, dashboard.root.grpcCallOptions);
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
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
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
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
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
        dashboard.root.processStreamDGRPCError(dashboard.root.dxProducerClient, error);
    }

    function updateWiFiInfo() {
        if (!dashboard.root || !dashboard.root.platform) {
            return;
        }
        var wifiInfo = dashboard.root.platform.getCurrentWiFiConnection();
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
        if (!dashboard.root || !dashboard.root.platform) {
            return;
        }
        var channelsQualityInfo = dashboard.root.platform.getChannelsQualityInfo();
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

    function injectDiagnosticsSubtitles() {
        var platform = dashboard.root ? dashboard.root.platform : null;
        if (!platform) {
            return;
        }
        var currentDiagnostics = {
            "latencyPreSending": Math.round(sendingLatencyText.preSendingLatency),
            "latencySending": Math.round(sendingLatencyText.sendingLatency),
            "fpsInput": inputFPSText.inputFPS < 0 ? -1 : Math.round(inputFPSText.inputFPS),
            "fpsOutput": outputFPSText.outputFPS < 0 ? -1 : Math.round(outputFPSText.outputFPS),
            "bitrateVideo": encodingBitrateText.videoBitrate,
            "playerLagMin": Math.round(playerLagText.playerLagMin),
            "playerLagMax": Math.round(playerLagText.playerLagMax),
            "pingRtt": pingStatus.rttMS,
            "wifiSsid": wifiStatus.ssid,
            "wifiBssid": wifiStatus.bssid,
            "wifiRssi": wifiStatus.rssi,
            "channels": [channel1Quality.quality, channel2Quality.quality, channel3Quality.quality],
            "viewersYoutube": youtubeCounter.value,
            "viewersTwitch": twitchCounter.value,
            "viewersKick": kickCounter.value,
            "signal": signalStatus.signalStrength,
            "streamTime": Math.round(statusStreamTime.seconds),
            "cpuUtilization": platform.cpuUtilization,
            "memoryUtilization": platform.memoryUtilization,
            "temperatures": platform.temperatures
        };

        var msg = {};
        var hasChanges = false;
        var isFullState = (diagnosticsUpdateCount % 10) === 0;

        for (var key in currentDiagnostics) {
            if (key === "channels" || key === "temperatures") {
                if (isFullState || JSON.stringify(currentDiagnostics[key]) !== JSON.stringify(lastDiagnostics[key])) {
                    msg[key] = currentDiagnostics[key];
                    hasChanges = true;
                }
                continue;
            }
            if (isFullState || currentDiagnostics[key] !== lastDiagnostics[key]) {
                msg[key] = currentDiagnostics[key];
                hasChanges = true;
            }
        }

        if (!hasChanges) {
            diagnosticsUpdateCount++;
            return;
        }

        diagnosticsUpdateCount++;
        lastDiagnostics = currentDiagnostics;

        if (!dashboard.root.checkFFStreamClient()) {
            return;
        }
        if (!dashboard.root.ffstreamClient.isChannelReady()) {
            return;
        }
        dashboard.root.ffstreamClient.injectDiagnostics(msg, 1000000000, function () {}, function (error) {
            dashboard.root.processFFStreamGRPCError(dashboard.root.ffstreamClient, error);
        }, dashboard.root.grpcCallOptions);
    }

    Connections {
        target: dashboard.root ? dashboard.root.platform : null
        function onSignalStrengthChanged(strength) {
            console.log("new value of the signal strength: " + strength);
            signalStatus.signalStrength = strength;
        }
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

    function pingColorFromMS(durMS, thresholdGood, thresholdWarn, thresholdBad) {
        if (durMS < 0) {
            return '#FF0000';
        }
        if (durMS < thresholdGood) {
            return '#00FF00';
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

    function cpuUtilizationColor(util) {
        if (util < 0.2)
            return '#00FF00';
        if (util < 0.5)
            return colorMix('#00FF00', '#FFFF00', (util - 0.2) / 0.3);
        if (util < 0.8)
            return colorMix('#FFFF00', '#FF0000', (util - 0.6) / 0.2);
        return '#FF0000';
    }

    function memUtilizationColor(util) {
        if (util < 0.5)
            return '#00FF00';
        if (util < 0.75)
            return colorMix('#00FF00', '#FFFF00', (util - 0.5) / 0.25);
        if (util < 0.9)
            return colorMix('#FFFF00', '#FF0000', (util - 0.75) / 0.15);
        return '#FF0000';
    }

    function temperatureColor(temp, type) {
        var low = 40;
        var warn = 70;
        var high = 90;

        if (!type) {
            type = "";
        }

        if (type.indexOf("batt") !== -1 || type.indexOf("bms") !== -1) {
            low = 35;
            warn = 42;
            high = 48;
        } else if (type.indexOf("cpu") !== -1 || type.indexOf("gpu") !== -1 || type.indexOf("g3d") !== -1 || type.indexOf("tpu") !== -1 || type.indexOf("soc") !== -1) {
            low = 50;
            warn = 85;
            high = 100;
        } else if (type.indexOf("skin") !== -1 || type.indexOf("ext_") !== -1 || type.indexOf("usb") !== -1 || type.indexOf("charger") !== -1) {
            low = 35;
            warn = 40;
            high = 45;
        }

        if (temp < low)
            return '#00FF00';
        if (temp < warn)
            return colorMix('#00FF00', '#FFFF00', (temp - low) / (warn - low));
        if (temp < high)
            return colorMix('#FFFF00', '#FF0000', (temp - warn) / (high - warn));
        return '#FF0000';
    }

    function formatDuration(durationMS) {
        if (durationMS < 200) {
            return Math.round(durationMS) + " ms";
        }
        var deciSeconds = Math.floor(durationMS / 100);
        var minutes = Math.floor(deciSeconds / 600);
        var seconds = Math.floor(deciSeconds / 10) % 60;
        if (minutes < 1) {
            deciSeconds -= seconds * 10;
            return seconds + "." + Math.floor(deciSeconds);
        }
        if (minutes < 60) {
            return minutes + ":" + seconds;
        }
        var hours = Math.floor(minutes / 60);
        minutes = minutes % 60;
        return hours + ":" + minutes + ":" + seconds;
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

    // Extract hostname from the streamd gRPC address (e.g.
    // "http://192.168.0.173:3594" → "192.168.0.173") so the preview
    // URL points at the same host instead of a hardcoded IP.
    function streamdHost() {
        var addr = main.dxProducerHost || "";
        // Strip protocol prefix if present.
        var host = addr.replace(/^https?:\/\//, "");
        // Strip port suffix if present.
        host = host.replace(/:[0-9]+\/?$/, "");
        return host || "127.0.0.1";
    }

    VideoPlayerRTMP {
        id: imageScreenshot
        anchors.top: statusBarTop.bottom
        width: parent.width
        height: parent.width * 9 / 16
        property string configuredPreview: dashboard.root.appSettings.previewRTMPUrl
        property string sourceRawCamera: "rtmp://127.0.0.1:1935/proxy/dji-osmo-pocket3"
        property string lowBitRatePreview: "rtmp://127.0.0.1:1935/proxy/dji-osmo-pocket3?reason=low-bitrate"
        property bool useLowBitratePreview: false
        property bool useRawSource: false
        readonly property string effectivePreview: useLowBitratePreview
            ? lowBitRatePreview
            : configuredPreview
        source: useRawSource ? sourceRawCamera : effectivePreview

        onEffectivePreviewChanged: {
            console.log("Dashboard preview URL:", effectivePreview);
        }

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
            onToggled: function () {
                console.log("toggling video source to ", checked ? "raw" : "prod");
                imageScreenshot.useRawSource = videoSourceToggle.checked;
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

            Rectangle {
                id: channel1Quality
                width: 20
                height: 20
                radius: 10
                color: "transparent"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                property int quality: -32768
                border.color: dashboard.channelQualityColor(quality)
                visible: quality > -32768
                Text {
                    anchors.centerIn: parent
                    text: "S"
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.border.color
                }
            }
            Rectangle {
                id: channel2Quality
                width: 20
                height: 20
                radius: 10
                color: "transparent"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                property int quality: -32768
                border.color: dashboard.channelQualityColor(quality)
                visible: quality > -32768
                Text {
                    anchors.centerIn: parent
                    text: "P"
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.border.color
                }
            }
            Rectangle {
                id: channel3Quality
                width: 20
                height: 20
                radius: 10
                color: "transparent"
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                property int quality: -32768
                border.color: dashboard.channelQualityColor(quality)
                visible: quality > -32768
                Text {
                    anchors.centerIn: parent
                    text: "W"
                    font.pixelSize: 12
                    font.bold: true
                    color: parent.border.color
                }
            }
            Text {
                height: parent.height
                font.pixelSize: 20
                font.bold: true
                text: "|"
            }
            Column {
                width: 34
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    spacing: 2
                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: "transparent"
                        border.color: dashboard.cpuUtilizationColor(dashboard.root.platform.cpuUtilization)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "C"
                            font.pixelSize: 8
                            font.bold: true
                            color: parent.border.color
                        }
                    }
                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: "transparent"
                        border.color: dashboard.memUtilizationColor(dashboard.root.platform.memoryUtilization)
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "M"
                            font.pixelSize: 8
                            font.bold: true
                            color: parent.border.color
                        }
                    }
                }
                Row {
                    spacing: 2
                    Repeater {
                        model: {
                            var cpu = {
                                temp: -1337,
                                type: "cpu",
                                weight: -1e9,
                                icon: "C"
                            };
                            var batt = {
                                temp: -1337,
                                type: "batt",
                                weight: -1e9,
                                icon: "B"
                            };
                            var other = {
                                temp: -1337,
                                type: "other",
                                weight: -1e9,
                                icon: "O"
                            };

                            function getWeight(temp, type) {
                                var low = 40, high = 90;
                                if (!type)
                                    type = "";
                                var t = type.toLowerCase();
                                if (t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1) {
                                    low = 35;
                                    high = 48;
                                } else if (t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1 || t.indexOf("g3d") !== -1 || t.indexOf("tpu") !== -1 || t.indexOf("soc") !== -1) {
                                    low = 50;
                                    high = 100;
                                } else if (t.indexOf("skin") !== -1 || t.indexOf("ext_") !== -1 || t.indexOf("usb") !== -1 || t.indexOf("charger") !== -1) {
                                    low = 45;
                                    high = 70;
                                }
                                return (temp - low) / (high - low);
                            }

                            for (var i = 0; i < dashboard.root.platform.temperatures.length; i++) {
                                var t = dashboard.root.platform.temperatures[i];
                                var typeStr = (t.type || "").toLowerCase();
                                var weight = getWeight(t.temp, typeStr);

                                if (typeStr.indexOf("cpu") !== -1 || typeStr.indexOf("gpu") !== -1 || typeStr.indexOf("g3d") !== -1 || typeStr.indexOf("tpu") !== -1 || typeStr.indexOf("soc") !== -1) {
                                    if (weight > cpu.weight) {
                                        cpu.temp = t.temp;
                                        cpu.type = t.type;
                                        cpu.weight = weight;
                                    }
                                } else if (typeStr.indexOf("batt") !== -1 || typeStr.indexOf("bms") !== -1) {
                                    if (weight > batt.weight) {
                                        batt.temp = t.temp;
                                        batt.type = t.type;
                                        batt.weight = weight;
                                    }
                                } else {
                                    if (weight > other.weight) {
                                        other.temp = t.temp;
                                        other.type = t.type;
                                        other.weight = weight;
                                    }
                                }
                            }
                            var res = [];
                            if (cpu.temp > -1337)
                                res.push(cpu);
                            if (batt.temp > -1337)
                                res.push(batt);
                            if (other.temp > -1337)
                                res.push(other);
                            return res;
                        }
                        Rectangle {
                            id: temperatureIndicator
                            required property var modelData
                            width: 10
                            height: 10
                            radius: 5
                            color: "transparent"
                            border.color: dashboard.temperatureColor(modelData.temp, modelData.type)
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: temperatureIndicator.modelData.icon
                                font.pixelSize: 8
                                font.bold: true
                                color: parent.border.color
                            }
                        }
                    }
                }
            }

            Text {
                id: sendingLatencyText
                height: parent.height
                width: 180
                leftPadding: 8
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignRight
                property real preSendingLatency: 0
                property real sendingLatency: 0
                text: (preSendingLatency < 0 || sendingLatency < 0 ? "N/A" : dashboard.formatDuration(preSendingLatency) + "+" + dashboard.formatDuration(sendingLatency)) + "📱"
                color: dashboard.pingColorFromMS(preSendingLatency + sendingLatency, 100, 400, 1500)
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
                color: dashboard.pingColorFromMS(rttMS, 20, 100, 1000)

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
                property real inputFPS: -1
                text: "in-FPS: " + (inputFPS < 0 ? "N/A" : Math.round(inputFPS * 10) / 10)
                color: dashboard.fpsColor(inputFPS, 15, 21, 24)
            }

            Text {
                id: outputFPSText
                height: parent.height
                width: 110
                font.pixelSize: 20
                font.bold: true
                horizontalAlignment: Text.AlignRight
                property int outputFPS: -1
                text: "out-FPS: " + (outputFPS < 0 ? "N/A" : outputFPS)
                color: dashboard.fpsColor(outputFPS, 5, 10, 29)
            }

            Text {
                id: encodingBitrateText
                height: parent.height
                width: 90
                font.pixelSize: 20
                font.bold: true
                property int videoBitrate: -1
                text: "enc: " + (videoBitrate < 0 ? "N/A" : dashboard.formatBandwidth(videoBitrate))
                color: dashboard.bwColor(videoBitrate, 50000, 1000000, 5000000)
                onVideoBitrateChanged: {
                    if (videoBitrate <= 0) {
                        return;
                    }
                    imageScreenshot.useLowBitratePreview = videoBitrate < 2000000;
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

    Flow {
        id: toggleBar
        y: statusBarBottom.y + statusBarBottom.height
        x: 0
        width: parent.width
        spacing: 4
        padding: 4
        z: 1

        CheckBox {
            id: musicToggleBtn
            property bool musicEnabled: false
            text: "Music"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
            checked: musicEnabled
            nextCheckState: function() {
                var newVal = !musicEnabled;
                var val = newVal ? "true" : "false";
                dxProducerClient.setVariable("obs_music_enabled", val,
                    function() { musicEnabled = newVal; },
                    function(err) { processStreamDGRPCError(dxProducerClient, err); },
                    grpcCallOptions);
                return musicEnabled ? Qt.Checked : Qt.Unchecked;
            }
            Component.onCompleted: {
                dxProducerClient.getVariable("obs_music_enabled",
                    function(reply) { musicEnabled = (reply.value.toString() === "true"); },
                    function(err) { /* default false */ },
                    grpcCallOptions);
            }
        }

        CheckBox {
            id: subtitlesToggleBtn
            property bool subtitlesEnabled: false
            text: "Subs"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
            checked: subtitlesEnabled
            nextCheckState: function() {
                var newVal = !subtitlesEnabled;
                var val = newVal ? "true" : "false";
                dxProducerClient.setVariable("subtitles_enabled", val,
                    function() { subtitlesEnabled = newVal; },
                    function(err) { processStreamDGRPCError(dxProducerClient, err); },
                    grpcCallOptions);
                return subtitlesEnabled ? Qt.Checked : Qt.Unchecked;
            }
            Component.onCompleted: {
                dxProducerClient.getVariable("subtitles_enabled",
                    function(reply) { subtitlesEnabled = (reply.value.toString() === "true"); },
                    function(err) { /* default false */ },
                    grpcCallOptions);
            }
        }

        CheckBox {
            id: soundToggleBtn
            text: "Sound"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
            checked: appSettings.soundEnabled
            nextCheckState: function() {
                appSettings.soundEnabled = !appSettings.soundEnabled;
                return appSettings.soundEnabled ? Qt.Checked : Qt.Unchecked;
            }
        }

        CheckBox {
            id: vibrateToggleBtn
            checked: true
            text: "Vibrate"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
        }

        CheckBox {
            id: simpleNicksToggleBtn
            text: "Nick:simple"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
        }

        CheckBox {
            id: ttsToggleBtn
            enabled: chatView.ttsAvailable
            text: "TTS"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
        }

        CheckBox {
            id: ttsTellNamesToggleBtn
            enabled: ttsToggleBtn.checked
            text: "TTS:name"
            topPadding: 2; bottomPadding: 2
            font.pixelSize: 12
        }
    }

    ChatView {
        id: chatView
        root: dashboard.root
        model: dashboard.root.globalChatMessagesModel
        soundEnabled: appSettings.soundEnabled
        platformCapabilities: dashboard.platformCapabilities
        vibrateEnabled: vibrateToggleBtn.checked
        simpleNicks: simpleNicksToggleBtn.checked
        ttsOn: ttsToggleBtn.checked
        ttsTellNames: ttsTellNamesToggleBtn.checked
        y: toggleBar.y + toggleBar.height + 2
        width: parent.width
        height: parent.height - y - chatReplyBar.height

        onRequestBanUser: function(platID, userID, reason, deadlineUnixMs) {
            console.log("Ban user:", platID, userID, reason, deadlineUnixMs);
            dxProducerClient.banUser(platID, userID, reason, deadlineUnixMs,
                function() { console.log("ban ok:", platID, userID); },
                function(err) { console.warn("ban failed:", err); },
                grpcCallOptions);
        }
        onRequestRemoveChatMessage: function(platID, messageID) {
            console.log("Remove chat message:", platID, messageID);
            dxProducerClient.removeChatMessage(platID, messageID,
                function() { console.log("delete ok:", platID, messageID); },
                function(err) { console.warn("delete failed:", err); },
                grpcCallOptions);
        }

        Component.onCompleted: function () {
            console.log("ChatView: x,y,w,h: ", x, y, width, height);
        }
    }

    Row {
        id: chatReplyBar
        x: 0
        y: parent.height - height
        width: parent.width
        height: 44
        spacing: 4

        ComboBox {
            id: chatPlatformSelector
            width: 80
            height: parent.height
            model: ["twitch", "youtube", "kick"]
            font.pixelSize: 12
        }

        TextField {
            id: chatMessageInput
            width: parent.width - chatPlatformSelector.width - chatSendBtn.width - parent.spacing * 2
            height: parent.height
            placeholderText: "Send a message..."
            font.pixelSize: 14
            onAccepted: chatSendBtn.sendMessage()
        }

        Button {
            id: chatSendBtn
            width: 60
            height: parent.height
            text: "Send"
            font.pixelSize: 12
            enabled: chatMessageInput.text.length > 0

            function sendMessage() {
                var platID = chatPlatformSelector.currentText;
                var msg = chatMessageInput.text.trim();
                if (msg.length === 0) {
                    return;
                }
                dxProducerClient.SendChatMessage({
                    platID: platID,
                    message: msg
                }, function () {
                    console.log("Chat message sent to", platID);
                    chatMessageInput.text = "";
                }, function (error) {
                    console.warn("SendChatMessage failed:", error);
                    processStreamDGRPCError(dxProducerClient, error);
                }, grpcCallOptions);
            }

            onClicked: sendMessage()
        }
    }
}
