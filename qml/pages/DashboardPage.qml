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
    property string wifiBssid: ""
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

    // TTS / vibration / sound (persisted via settings)
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
                root.wifiBssid = conn.bssid || ""
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

            if (root.settings.ttsEnabled && tts.state !== TextToSpeech.Error) {
                var ttsText = cleanText
                if (root.settings.ttsUsernames) {
                    var speakName = displayName || userName
                    ttsText = "from " + speakName + ": " + ttsText
                }
                tts.enqueue(ttsText)
            } else if (root.settings.soundEnabled) {
                chatSound.play()
            }

            if (root.settings.vibrateEnabled)
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

    function formatSSID(ssid, bssid) {
        if (!ssid || ssid === "") return "\uD83D\uDEAB"
        var b = (bssid || "").toUpperCase()
        switch (ssid) {
        case "home.dx.center":
        case "dslmodem.dx.center":
        case "slow.dslmodem.dx.center":
            switch (b) {
            case "A8:29:48:3E:E2:F4": return "\uD83C\uDFE1\u25C9"
            case "A8:29:48:3E:E7:A6": return "\uD83C\uDFD8\u25C9"
            case "A8:29:48:3E:E3:B2": return "\uD83C\uDFE0\u25C9"
            case "3C:A6:2F:15:B1:04": return "\u260E\u25C9"
            default: return "?\uD83C\uDFE0\u25C9"
            }
        default:
            return "\uD83D\uDEDC\u25C9"
        }
    }

    function usernameColor(name) {
        var hash = 0
        for (var i = 0; i < name.length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash)
        }
        var h = Math.abs(hash) % 360
        return Qt.hsla(h / 360.0, 0.7, 0.6, 1.0)
    }

    function platformColor(platform) {
        if (platform === "twitch") return Theme.twitch
        if (platform === "youtube") return Theme.youtube
        if (platform === "kick") return Theme.kick
        return Theme.textTertiary
    }

    function colorToHex(c) {
        var r = Math.round(c.r * 255).toString(16)
        var g = Math.round(c.g * 255).toString(16)
        var b = Math.round(c.b * 255).toString(16)
        if (r.length < 2) r = "0" + r
        if (g.length < 2) g = "0" + g
        if (b.length < 2) b = "0" + b
        return "#" + r + g + b
    }

    function escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
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

                    // Categorize thermal zones by vendor-specific patterns:
                    // CPU: cpu, gpu, g3d, tpu, soc, tsens (Qualcomm), npu
                    // Battery: batt, bms
                    // Skin: skin, quiet-therm (Qualcomm board), mtktsap (MediaTek board)
                    // Excluded: xo-therm, msm-therm, pa-therm (SoC-internal, misleadingly hot)
                    function isCpu(t) {
                        return t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1
                            || t.indexOf("g3d") !== -1 || t.indexOf("tpu") !== -1
                            || t.indexOf("npu") !== -1 || t.indexOf("soc") !== -1
                            || t.indexOf("tsens") !== -1
                    }
                    function isBattery(t) {
                        return t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1
                    }
                    function isSkin(t) {
                        return t.indexOf("skin") !== -1 || t.indexOf("case") !== -1
                            || t.indexOf("ambient") !== -1
                            || t.indexOf("quiet-therm") !== -1 || t.indexOf("quiet_therm") !== -1
                            || t.indexOf("mtktsap") !== -1
                    }

                    function getWeight(temp, type) {
                        var low = 40, high = 90
                        if (isBattery(type)) { low = 35; high = 48 }
                        else if (isCpu(type)) { low = 50; high = 100 }
                        else if (isSkin(type)) { low = 30; high = 45 }
                        return (temp - low) / (high - low)
                    }

                    var cpu  = { temp: -1337, type: "", weight: -Infinity }
                    var batt = { temp: -1337, type: "", weight: -Infinity }
                    var skin = { temp: -1337, type: "", weight: -Infinity }

                    for (var i = 0; i < all.length; i++) {
                        var typeStr = (all[i].type || "").toLowerCase()
                        var w = getWeight(all[i].temp, typeStr)

                        if (isCpu(typeStr)) {
                            if (w > cpu.weight) { cpu.temp = all[i].temp; cpu.type = all[i].type; cpu.weight = w }
                        } else if (isBattery(typeStr)) {
                            if (w > batt.weight) { batt.temp = all[i].temp; batt.type = all[i].type; batt.weight = w }
                        } else if (isSkin(typeStr)) {
                            if (w > skin.weight) { skin.temp = all[i].temp; skin.type = all[i].type; skin.weight = w }
                        }
                    }

                    var result = []
                    if (cpu.temp > -1337) result.push({ label: "C", temp: cpu.temp, sensor: "cpu" })
                    if (batt.temp > -1337) result.push({ label: "B", temp: batt.temp, sensor: "battery" })
                    if (skin.temp > -1337) result.push({ label: "S", temp: skin.temp, sensor: "skin" })
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

            // WiFi icon + RSSI
            Text {
                text: root.wifiSsid !== ""
                    ? root.formatSSID(root.wifiSsid, root.wifiBssid) + " " + root.wifiRssi
                    : root.formatSSID("", "")
                font.pixelSize: Theme.fontTiny
                font.weight: Font.Medium
                color: root.wifiSsid !== "" ? Theme.rssiColor(root.wifiRssi) : Theme.textTertiary
            }
        }

        // TTS / vibration / sound toggles (compact circles)
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Repeater {
                model: [
                    { key: "tts",     letter: "T", tip: "TTS" },
                    { key: "ttsName", letter: "N", tip: "TTS:name" },
                    { key: "vibrate", letter: "V", tip: "Vibrate" },
                    { key: "sound",   letter: "S", tip: "Sound" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    property bool active: {
                        if (modelData.key === "tts") return root.settings.ttsEnabled
                        if (modelData.key === "ttsName") return root.settings.ttsUsernames
                        if (modelData.key === "vibrate") return root.settings.vibrateEnabled
                        return root.settings.soundEnabled
                    }
                    property bool allowed: modelData.key !== "ttsName" || root.settings.ttsEnabled
                    objectName: "dashboard" + modelData.tip.replace(":", "") + "Toggle"
                    width: 24; height: 24; radius: 12
                    color: active ? Theme.accentSecondary : "transparent"
                    border.width: active ? 0 : 1
                    border.color: active ? "transparent" : Theme.textTertiary
                    opacity: allowed ? 1.0 : 0.3
                    Text {
                        anchors.centerIn: parent
                        text: modelData.letter
                        font.pixelSize: Theme.fontSmall
                        font.weight: Font.Bold
                        color: parent.active ? "#FFFFFF" : Theme.textSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: parent.allowed
                        onClicked: {
                            if (modelData.key === "tts") {
                                root.settings.ttsEnabled = !root.settings.ttsEnabled
                                if (!root.settings.ttsEnabled) tts.stop()
                            } else if (modelData.key === "ttsName") {
                                root.settings.ttsUsernames = !root.settings.ttsUsernames
                            } else if (modelData.key === "vibrate") {
                                root.settings.vibrateEnabled = !root.settings.vibrateEnabled
                            } else {
                                root.settings.soundEnabled = !root.settings.soundEnabled
                            }
                        }
                    }
                }
            }
        }

        // Chat view (fills remaining space)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: chatList
                objectName: "dashboardChat"
                anchors.fill: parent
                model: root.messages
                clip: true
                spacing: Theme.spacingTiny
                verticalLayoutDirection: ListView.TopToBottom
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 100000
                maximumFlickVelocity: 100000

                property bool userScrolledUp: false

                onMovingVerticallyChanged: {
                    if (!movingVertically) {
                        userScrolledUp = !atYEnd
                    }
                }

                onAtYEndChanged: {
                    if (atYEnd) userScrolledUp = false
                }

                onCountChanged: {
                    if (!userScrolledUp) {
                        Qt.callLater(function() { chatList.positionViewAtEnd() })
                    }
                }

                delegate: Item {
                    width: chatList.width
                    implicitHeight: msgLine.implicitHeight + Theme.spacingTiny

                    Text {
                        id: msgLine
                        width: parent.width
                        wrapMode: Text.Wrap
                        textFormat: Text.StyledText
                        font.pixelSize: root.settings.chatFontSize
                        color: Theme.textPrimary
                        text: {
                            var platColor = root.platformColor(model.platform)
                            var hex = root.colorToHex(platColor)
                            var ts = root.formatTimestamp(model.timestamp)
                            var prefix = ""
                            if (ts !== "") {
                                prefix = "<font color=\"" + hex + "\" size=\"2\">" + ts + "</font> "
                            } else {
                                prefix = "<font color=\"" + hex + "\">&#x25CF;</font> "
                            }
                            var name = model.userName || "Anonymous"
                            var nameHex = root.colorToHex(root.usernameColor(name))
                            var nameHtml = "<font color=\"" + nameHex + "\"><b>" + root.escapeHtml(name) + "</b></font> "
                            return prefix + nameHtml + root.escapeHtml(model.message || "")
                        }
                    }
                }
            }

            // Scroll-to-bottom button
            Rectangle {
                visible: chatList.userScrolledUp
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.bottomMargin: Theme.spacingSmall
                anchors.rightMargin: Theme.spacingSmall
                width: 48; height: 48; radius: 24
                color: Theme.accentPrimary
                opacity: 0.9

                Text {
                    anchors.centerIn: parent
                    text: "\u25BC"
                    font.pixelSize: 22
                    color: "#FFFFFF"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        chatList.positionViewAtEnd()
                        chatList.userScrolledUp = false
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
