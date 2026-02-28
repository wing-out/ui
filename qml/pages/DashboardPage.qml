import QtQuick
import QtQuick.Layouts
import QtMultimedia
import QtTextToSpeech
import "../components" as Components
import WingOut

Item {
    id: root

    Accessible.name: "dashboardPage"
    Accessible.role: Accessible.Pane

    required property var controller
    required property var settings

    // Metrics state
    property real inputBitrate: 0
    property real videoLatency: 0
    property real inputFPS: 0
    property real pingRtt: 0
    property real outputFPS: 0
    property real encodedBitrate: 0
    property real inputContinuity: -1
    property real playerLagMs: -1
    property string wifiSsid: ""
    property int wifiRssi: 0
    property real preSendLatency: 0
    property real sendLatency: 0
    property var channelQualities: []
    property string firstPlayerId: ""

    // Viewer counts
    property int viewersTwitch: 0
    property int viewersYoutube: 0
    property int viewersKick: 0

    // Stream uptime tracking
    property int streamUptimeSeconds: 0
    property bool streamActive: false

    // Chat messages
    property var messages: ListModel {}

    // Platform send toggles
    property bool sendTwitch: true
    property bool sendYoutube: true
    property bool sendKick: true

    // TTS / vibration / sound
    property bool ttsEnabled: false
    property bool ttsUsernames: false
    property bool vibrateEnabled: false
    property bool soundEnabled: true
    property var botUsernames: ["savedggbot", "botrix", "botrixoficial", "nightbot", "streamelements"]

    function isBot(userName) {
        if (!userName) return false
        return botUsernames.indexOf(userName.toLowerCase()) >= 0
    }

    TextToSpeech { id: tts }
    SoundEffect { id: chatSound; source: "qrc:/audio/chat_message_add.wav" }

    Timer {
        id: uptimeTimer
        interval: 1000
        running: root.streamActive
        repeat: true
        onTriggered: root.streamUptimeSeconds++
    }

    // Polling timers
    Timer {
        id: bitrateTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            controller.getBitRates(
                function(result) {
                    root.inputBitrate = Theme.normalizeNumber(result.inputVideo, 0)
                    root.encodedBitrate = Theme.normalizeNumber(result.encodedVideo, 0)
                },
                function(err) {}
            )
        }
    }

    Timer {
        id: latencyTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            controller.getLatencies(
                function(result) {
                    var preSend = Theme.normalizeNumber(result.videoPreTranscoding, 0)
                        + Theme.normalizeNumber(result.videoTranscoding, 0)
                        + Theme.normalizeNumber(result.videoTranscodedPreSend, 0)
                    var send = Theme.normalizeNumber(result.videoSending, 0)
                    root.preSendLatency = preSend
                    root.sendLatency = send
                    root.videoLatency = preSend + send
                },
                function(err) {}
            )
        }
    }

    Timer {
        id: fpsTicker
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            controller.getFPSFraction(
                function(result) {
                    var num = Theme.normalizeNumber(result.num, 0)
                    var den = Theme.normalizeNumber(result.den, 1)
                    root.inputFPS = den > 0 ? num / den : 0
                },
                function(err) {}
            )
        }
    }

    Timer {
        id: pingTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: {
            var start = Date.now()
            controller.ping("p",
                function() { root.pingRtt = Date.now() - start },
                function() {}
            )
        }
    }

    // Stream status polling
    Timer {
        id: streamStatusTicker
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            controller.getStreamStatus("twitch", "", "", false,
                function(result) {
                    root.viewersTwitch = result.viewersCount || 0
                    if (result.isActive && !root.streamActive) {
                        root.streamActive = true
                        root.streamUptimeSeconds = 0
                    }
                },
                function(err) {}
            )
            controller.getStreamStatus("youtube", "", "", false,
                function(result) { root.viewersYoutube = result.viewersCount || 0 },
                function(err) {}
            )
            controller.getStreamStatus("kick", "", "", false,
                function(result) { root.viewersKick = result.viewersCount || 0 },
                function(err) {}
            )
        }
    }

    // Output quality polling (output FPS)
    Timer {
        id: outputQualityTicker
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            controller.getOutputQuality(
                function(result) {
                    root.outputFPS = Theme.normalizeNumber(result.videoFrameRate, 0)
                },
                function(err) {}
            )
        }
    }

    // Input quality polling (continuity)
    Timer {
        id: inputQualityTicker
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            controller.getInputQuality(
                function(result) {
                    root.inputContinuity = Theme.normalizeNumber(result.videoContinuity, -1)
                },
                function(err) {}
            )
        }
    }

    // Player lag polling
    Timer {
        id: playerLagTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            controller.listStreamPlayers(
                function(players) {
                    if (players && players.length > 0) {
                        root.firstPlayerId = players[0].id || ""
                        controller.playerGetLag(root.firstPlayerId,
                            function(lag) {
                                root.playerLagMs = Theme.normalizeNumber(lag, -1) * 1000
                            },
                            function(err) { root.playerLagMs = -1 }
                        )
                    } else {
                        root.firstPlayerId = ""
                        root.playerLagMs = -1
                    }
                },
                function(err) { root.playerLagMs = -1 }
            )
        }
    }

    // WiFi polling
    Timer {
        id: wifiTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            var conn = platformInstance.getCurrentWiFiConnection()
            if (conn) {
                root.wifiSsid = conn.ssid || ""
                root.wifiRssi = conn.rssi || 0
            } else {
                root.wifiSsid = ""
                root.wifiRssi = 0
            }
        }
    }

    // Channel quality polling (from gRPC)
    Timer {
        id: channelQualityTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            controller.getChannelQuality(
                function(channels) {
                    root.channelQualities = channels || []
                },
                function(err) {}
            )
        }
    }

    // Diagnostics injection
    Timer {
        id: diagnosticsTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            var diag = {
                "latencyPreSending": Math.round(root.preSendLatency / 1000),
                "latencySending": Math.round(root.sendLatency / 1000),
                "fpsInput": Math.round(root.inputFPS),
                "fpsOutput": Math.round(root.outputFPS),
                "bitrateVideo": Math.round(root.encodedBitrate),
                "pingRtt": Math.round(root.pingRtt),
                "viewersYoutube": root.viewersYoutube,
                "viewersTwitch": root.viewersTwitch,
                "viewersKick": root.viewersKick,
                "signal": platformInstance.signalStrength,
                "streamTime": root.streamUptimeSeconds,
                "cpuUtilization": platformInstance.cpuUtilization,
                "memoryUtilization": platformInstance.memoryUtilization
            }
            if (root.wifiSsid !== "") {
                diag.wifiSsid = root.wifiSsid
                diag.wifiRssi = root.wifiRssi
            }
            if (root.playerLagMs >= 0) {
                diag.playerLagMin = Math.round(root.playerLagMs)
                diag.playerLagMax = Math.round(root.playerLagMs)
            }
            if (root.channelQualities.length > 0) {
                var chs = []
                for (var i = 0; i < root.channelQualities.length; i++)
                    chs.push(root.channelQualities[i].quality || 0)
                diag.channels = chs
            }
            controller.injectDiagnostics(diag,
                function() {},
                function(err) {}
            )
        }
    }

    // Subscribe to chat messages
    Component.onCompleted: {
        controller.subscribeToChatMessages()
    }

    Connections {
        target: controller
        function onChatMessageReceived(message) {
            var userName = message.userName || ""
            var displayName = (message.user && message.user.nameReadable) ? message.user.nameReadable : userName
            var text = message.text || ""
            var platform = message.platform || ""

            root.messages.append({
                "messageId": message.messageId || "",
                "platform": platform,
                "userName": userName,
                "displayName": displayName,
                "message": text,
                "timestamp": message.timestamp || 0
            })

            if (root.isBot(userName)) return

            var cleanText = text.replace(/<[^>]*>/g, "")
            cleanText = cleanText.replace(/https?:\/\/[^\s]+/g, "<HTTP-link>")

            if (root.ttsEnabled && tts.state !== TextToSpeech.Error) {
                var ttsText = cleanText
                if (root.ttsUsernames) {
                    var speakName = displayName || userName
                    ttsText = "from " + speakName + ": " + ttsText
                }
                tts.enqueue(ttsText)
            } else if (root.soundEnabled) {
                chatSound.play()
            }

            if (root.vibrateEnabled)
                platformInstance.vibrate(500, true)
        }
    }

    function formatTimestamp(ts) {
        if (!ts) return ""
        var d = new Date(ts * 1000)
        if (isNaN(d.getTime())) return ""
        var fmt = root.settings.chatTimestampFormat
        var hh = String(d.getHours()).padStart(2, '0')
        var mm = String(d.getMinutes()).padStart(2, '0')
        var ss = String(d.getSeconds()).padStart(2, '0')
        if (fmt === "hh:mm:ss") return hh + ":" + mm + ":" + ss
        if (fmt === "hh:mm") return hh + ":" + mm
        if (fmt === "none") return ""
        return mm
    }

    function usernameColor(name) {
        var hash = 0
        for (var i = 0; i < name.length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash)
        }
        var h = Math.abs(hash) % 360
        return Qt.hsla(h / 360.0, 0.7, 0.6, 1.0)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // Status indicators row
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.StatusBadge {
                objectName: "dashboardTwitchBadge"
                label: "Twitch" + (root.viewersTwitch > 0 ? " (" + root.viewersTwitch + ")" : "")
                statusColor: root.viewersTwitch > 0 ? Theme.twitch : Theme.textTertiary
                active: root.viewersTwitch > 0
            }

            Components.StatusBadge {
                objectName: "dashboardYoutubeBadge"
                label: "YouTube" + (root.viewersYoutube > 0 ? " (" + root.viewersYoutube + ")" : "")
                statusColor: root.viewersYoutube > 0 ? Theme.youtube : Theme.textTertiary
                active: root.viewersYoutube > 0
            }

            Components.StatusBadge {
                objectName: "dashboardKickBadge"
                label: "Kick" + (root.viewersKick > 0 ? " (" + root.viewersKick + ")" : "")
                statusColor: root.viewersKick > 0 ? Theme.kick : Theme.textTertiary
                active: root.viewersKick > 0
            }

            Components.StatusBadge {
                objectName: "dashboardLiveBadge"
                label: root.streamActive ? "LIVE " + Theme.formatDuration(root.streamUptimeSeconds) : "OFFLINE"
                statusColor: root.streamActive ? Theme.error : Theme.textTertiary
                active: root.streamActive
            }
        }

        // Video preview (16:9 aspect ratio)
        Components.VideoPlayerRTMP {
            objectName: "dashboardVideoPreview"
            Layout.fillWidth: true
            Layout.preferredHeight: width * 9 / 16
            source: root.settings.previewRTMPUrl
            muted: true
        }

        // Compact metrics bar — Row 1
        Flow {
            objectName: "dashboardCompactMetrics"
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            // Channel quality labeled circles (dynamic from gRPC)
            Repeater {
                model: root.channelQualities
                delegate: Rectangle {
                    required property var modelData
                    width: 14; height: 14; radius: 7
                    color: Theme.channelQualityColor(modelData.quality || 0)
                    Text {
                        anchors.centerIn: parent
                        text: (modelData.label || "?").charAt(0)
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: "#FFFFFF"
                    }
                }
            }

            // Separator
            Text {
                text: "|"
                font.pixelSize: Theme.fontTiny
                color: Theme.textTertiary
                visible: root.channelQualities.length > 0
            }

            // CPU indicator
            Rectangle {
                width: 14; height: 14; radius: 7
                color: Theme.cpuColor(platformInstance.cpuUtilization)
                Text {
                    anchors.centerIn: parent
                    text: "C"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: "#FFFFFF"
                }
            }

            // Memory indicator
            Rectangle {
                width: 14; height: 14; radius: 7
                color: Theme.memColor(platformInstance.memoryUtilization)
                Text {
                    anchors.centerIn: parent
                    text: "M"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: "#FFFFFF"
                }
            }

            // Separator
            Text {
                text: "|"
                font.pixelSize: Theme.fontTiny
                color: Theme.textTertiary
            }

            // Temperature indicators (CPU, Battery, Other — hottest in each category)
            Repeater {
                model: {
                    var all = platformInstance.temperatures || []

                    function getWeight(temp, type) {
                        var low = 40, high = 90
                        if (!type) type = ""
                        var t = type.toLowerCase()
                        if (t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1) {
                            low = 35; high = 48
                        } else if (t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1
                                   || t.indexOf("g3d") !== -1 || t.indexOf("tpu") !== -1
                                   || t.indexOf("soc") !== -1) {
                            low = 50; high = 100
                        } else if (t.indexOf("skin") !== -1 || t.indexOf("ext_") !== -1
                                   || t.indexOf("usb") !== -1 || t.indexOf("charger") !== -1) {
                            low = 45; high = 70
                        }
                        return (temp - low) / (high - low)
                    }

                    var cpu  = { temp: -1337, type: "", weight: -Infinity }
                    var batt = { temp: -1337, type: "", weight: -Infinity }
                    var other = { temp: -1337, type: "", weight: -Infinity }

                    for (var i = 0; i < all.length; i++) {
                        var typeStr = (all[i].type || "").toLowerCase()
                        var w = getWeight(all[i].temp, typeStr)

                        if (typeStr.indexOf("cpu") !== -1 || typeStr.indexOf("gpu") !== -1
                            || typeStr.indexOf("g3d") !== -1 || typeStr.indexOf("tpu") !== -1
                            || typeStr.indexOf("soc") !== -1) {
                            if (w > cpu.weight) { cpu.temp = all[i].temp; cpu.type = all[i].type; cpu.weight = w }
                        } else if (typeStr.indexOf("batt") !== -1 || typeStr.indexOf("bms") !== -1) {
                            if (w > batt.weight) { batt.temp = all[i].temp; batt.type = all[i].type; batt.weight = w }
                        } else {
                            if (w > other.weight) { other.temp = all[i].temp; other.type = all[i].type; other.weight = w }
                        }
                    }

                    var result = []
                    if (cpu.temp > -1337) result.push({ label: "C", temp: cpu.temp, sensor: "cpu" })
                    if (batt.temp > -1337) result.push({ label: "B", temp: batt.temp, sensor: "battery" })
                    if (other.temp > -1337) result.push({ label: "O", temp: other.temp, sensor: "skin" })
                    return result
                }
                delegate: Row {
                    required property var modelData
                    spacing: 2
                    Rectangle {
                        width: 14; height: 14; radius: 7
                        color: Theme.temperatureColor(modelData.temp, modelData.sensor)
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: "#FFFFFF"
                        }
                    }
                    Text {
                        text: Math.round(modelData.temp) + "\u00B0"
                        font.pixelSize: Theme.fontTiny
                        font.weight: Font.Bold
                        color: Theme.temperatureColor(modelData.temp, modelData.sensor)
                    }
                }
            }

            // Separator
            Text {
                text: "|"
                font.pixelSize: Theme.fontTiny
                color: Theme.textTertiary
            }

            // Latency: pre+send ms
            Text {
                property real preMs: root.preSendLatency / 1000
                property real sendMs: root.sendLatency / 1000
                property bool hasData: preMs > 0 || sendMs > 0
                text: hasData
                    ? Math.round(preMs) + "+" + Math.round(sendMs) + "ms"
                    : "--+--ms"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: hasData ? Theme.latencyColor(preMs + sendMs) : Theme.textTertiary
                Accessible.name: "dashboardLatency"
            }

            // Separator
            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Ping RTT
            Text {
                text: root.pingRtt > 0 ? root.pingRtt.toFixed(0) + "ms" : "--ms"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.pingRtt > 0 ? Theme.pingColor(root.pingRtt) : Theme.textTertiary
                Accessible.name: "dashboardPing"
            }

            // Separator
            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Player lag
            Text {
                text: root.playerLagMs >= 0 ? (root.playerLagMs / 1000).toFixed(1) + "s lag" : "-- lag"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.playerLagMs >= 0 ? Theme.playerLagColor(root.playerLagMs) : Theme.textTertiary
            }

            // Separator
            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Signal strength
            Text {
                text: platformInstance.signalStrength !== 0
                    ? platformInstance.signalStrength + "dBm"
                    : "--dBm"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: platformInstance.signalStrength !== 0
                    ? Theme.rssiColor(platformInstance.signalStrength)
                    : Theme.textTertiary
            }
        }

        // Compact metrics bar — Row 2
        Flow {
            objectName: "dashboardCompactMetrics2"
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            // Input FPS
            Text {
                text: root.inputFPS > 0 ? "in:" + root.inputFPS.toFixed(1) + "fps" : "in:--fps"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.inputFPS > 0 ? Theme.fpsColor(root.inputFPS) : Theme.textTertiary
                Accessible.name: "dashboardFps"
            }

            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Output FPS
            Text {
                text: root.outputFPS > 0 ? "out:" + root.outputFPS.toFixed(1) + "fps" : "out:--fps"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.outputFPS > 0 ? Theme.fpsColor(root.outputFPS) : Theme.textTertiary
            }

            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Encoded bitrate
            Text {
                text: root.encodedBitrate > 0
                    ? "enc:" + Theme.formatBandwidth(root.encodedBitrate)
                    : "enc:--"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.encodedBitrate > 0 ? Theme.bitrateColor(root.encodedBitrate) : Theme.textTertiary
                Accessible.name: "dashboardBitrate"
            }

            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // Quality / continuity
            Text {
                text: root.inputContinuity >= 0
                    ? "Q:" + (root.inputContinuity * 100).toFixed(1) + "%"
                    : "Q:--%"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.inputContinuity >= 0 ? Theme.qualityColor(root.inputContinuity) : Theme.textTertiary
            }

            Text { text: "|"; font.pixelSize: Theme.fontTiny; color: Theme.textTertiary }

            // WiFi SSID + RSSI
            Text {
                text: root.wifiSsid !== ""
                    ? root.wifiSsid + " (" + root.wifiRssi + ")"
                    : "WiFi:--"
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.wifiSsid !== "" ? Theme.rssiColor(root.wifiRssi) : Theme.textTertiary
            }
        }

        // TTS / vibration / sound toggles
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.GlassButton {
                objectName: "dashboardTtsToggle"
                text: root.ttsEnabled ? "TTS ON" : "TTS OFF"
                filled: root.ttsEnabled
                accentColor: Theme.accentSecondary
                onClicked: {
                    root.ttsEnabled = !root.ttsEnabled
                    if (!root.ttsEnabled) tts.stop()
                }
            }

            Components.GlassButton {
                objectName: "dashboardTtsUsernamesToggle"
                text: root.ttsUsernames ? "TTS:name ON" : "TTS:name OFF"
                filled: root.ttsUsernames
                enabled: root.ttsEnabled
                accentColor: Theme.accentSecondary
                onClicked: root.ttsUsernames = !root.ttsUsernames
            }

            Components.GlassButton {
                objectName: "dashboardVibrateToggle"
                text: root.vibrateEnabled ? "Vibrate ON" : "Vibrate OFF"
                filled: root.vibrateEnabled
                onClicked: root.vibrateEnabled = !root.vibrateEnabled
            }

            Components.GlassButton {
                objectName: "dashboardSoundToggle"
                text: root.soundEnabled ? "Sound ON" : "Sound OFF"
                filled: root.soundEnabled
                onClicked: root.soundEnabled = !root.soundEnabled
            }
        }

        // Chat view (fills remaining space)
        ListView {
            id: chatList
            objectName: "dashboardChat"
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.messages
            clip: true
            spacing: Theme.spacingTiny
            verticalLayoutDirection: ListView.BottomToTop

            delegate: Item {
                width: chatList.width
                implicitHeight: msgRow.implicitHeight + Theme.spacingTiny

                Row {
                    id: msgRow
                    width: parent.width
                    spacing: Theme.spacingSmall

                    Text {
                        property string ts: root.formatTimestamp(model.timestamp)
                        visible: ts !== ""
                        text: ts
                        font.pixelSize: Theme.fontTiny
                        color: {
                            if (model.platform === "twitch") return Theme.twitch
                            if (model.platform === "youtube") return Theme.youtube
                            if (model.platform === "kick") return Theme.kick
                            return Theme.textTertiary
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: {
                            if (model.platform === "twitch") return Theme.twitch
                            if (model.platform === "youtube") return Theme.youtube
                            if (model.platform === "kick") return Theme.kick
                            return Theme.textTertiary
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: model.userName || "Anonymous"
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.Bold
                        color: root.usernameColor(model.userName || "Anonymous")
                    }

                    Text {
                        text: model.message || ""
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        width: parent.width - x
                    }
                }
            }
        }

        // Chat input row with platform toggles
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            // Platform send toggles: compact colored circles with letter
            Repeater {
                model: [
                    { key: "twitch",  letter: "T", color: Theme.twitch },
                    { key: "youtube", letter: "Y", color: Theme.youtube },
                    { key: "kick",    letter: "K", color: Theme.kick }
                ]
                delegate: Rectangle {
                    required property var modelData
                    property bool active: {
                        if (modelData.key === "twitch") return root.sendTwitch
                        if (modelData.key === "youtube") return root.sendYoutube
                        return root.sendKick
                    }
                    width: 28; height: 28; radius: 14
                    color: active ? modelData.color : "transparent"
                    border.width: active ? 0 : 2
                    border.color: active ? "transparent" : modelData.color
                    opacity: active ? 1.0 : 0.4
                    anchors.verticalCenter: parent.verticalCenter

                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.letter
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.Bold
                        color: parent.active ? "#FFFFFF" : modelData.color
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.key === "twitch") root.sendTwitch = !root.sendTwitch
                            else if (modelData.key === "youtube") root.sendYoutube = !root.sendYoutube
                            else root.sendKick = !root.sendKick
                        }
                    }
                }
            }

            Components.SearchField {
                id: chatInput
                objectName: "dashboardChatInput"
                width: parent.width - sendBtn.width - 3 * (28 + Theme.spacingSmall) - Theme.spacingSmall
                placeholder: "Type a message..."
            }

            Components.GlassButton {
                id: sendBtn
                objectName: "dashboardChatSend"
                text: "Send"
                filled: true
                width: 80
                enabled: chatInput.text.length > 0 && (root.sendTwitch || root.sendYoutube || root.sendKick)
                onClicked: {
                    if (chatInput.text.length === 0) return
                    var platforms = []
                    if (root.sendTwitch) platforms.push("twitch")
                    if (root.sendYoutube) platforms.push("youtube")
                    if (root.sendKick) platforms.push("kick")
                    var remaining = platforms.length
                    for (var i = 0; i < platforms.length; i++) {
                        controller.sendChatMessage(platforms[i], chatInput.text,
                            function() {
                                remaining--
                                if (remaining <= 0) chatInput.text = ""
                            },
                            function(err) {
                                remaining--
                                console.warn("sendChatMessage error:", err)
                                if (remaining <= 0) chatInput.text = ""
                            }
                        )
                    }
                }
            }
        }
    }
}
