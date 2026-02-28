import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root

    Accessible.name: "statusPage"
    Accessible.role: Accessible.Pane

    required property var controller

    // Metrics state
    property real inputBitrate: 0
    property real outputBitrate: 0
    property real videoLatency: 0
    property real latencyPreTranscoding: 0
    property real latencyTranscoding: 0
    property real latencySending: 0
    property real inputFPS: 0
    property real outputFPS: 0
    property real videoContinuity: 0
    property real pingRtt: 0
    property int viewersTwitch: 0
    property int viewersYoutube: 0
    property int viewersKick: 0

    // Player lag tracking
    property real playerLagMin: -1
    property real playerLagMax: -1
    property int playerLagLastUpdateAt: -1

    // WiFi info
    property string wifiSsid: ""
    property string wifiBssid: ""
    property int wifiRssi: -32768

    // Channel quality
    property var channelQualities: []

    // Diagnostics injection state
    property var lastDiagnostics: ({})
    property int diagnosticsUpdateCount: 0

    // Stream uptime tracking
    property int streamUptimeSeconds: 0
    property bool streamActive: false

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
        onTriggered: root.updateBitRates()
    }

    Timer {
        id: latencyTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: root.updateLatencies()
    }

    Timer {
        id: qualityTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: root.updateQuality()
    }

    Timer {
        id: fpsTicker
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.updateFPS()
    }

    Timer {
        id: pingTicker
        interval: 200
        running: true
        repeat: true
        onTriggered: root.doPing()
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
                    } else if (!result.isActive && root.streamActive) {
                        // Check if any other platform is still active before marking inactive
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

    // Player lag polling
    Timer {
        id: playerLagTicker
        interval: 500
        running: true
        repeat: true
        onTriggered: root.fetchPlayerLag()
    }

    // Player lag countdown (decrements min between fetches)
    Timer {
        id: playerLagUpdateTicker
        interval: 100
        running: true
        repeat: true
        onTriggered: root.updatePlayerLag()
    }

    // WiFi info polling
    Timer {
        id: wifiInfoTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.updateWiFiInfo()
    }

    // Channel quality polling
    Timer {
        id: channelQualityTicker
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.updateChannelQualityInfo()
    }

    // Diagnostics injection timer (1 second interval)
    Timer {
        id: diagnosticsInjectionTicker
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.injectDiagnosticsSubtitles()
    }

    function updateBitRates() {
        controller.getBitRates(
            function(result) {
                root.inputBitrate = Theme.normalizeNumber(result.inputVideo, 0)
                root.outputBitrate = Theme.normalizeNumber(result.outputVideo, 0)
            },
            function(err) { console.warn("getBitRates error:", err) }
        )
    }

    function updateLatencies() {
        controller.getLatencies(
            function(result) {
                root.latencyPreTranscoding = Theme.normalizeNumber(result.videoPreTranscoding, 0)
                root.latencyTranscoding = Theme.normalizeNumber(result.videoTranscoding, 0)
                root.latencySending = Theme.normalizeNumber(result.videoSending, 0)
                root.videoLatency = root.latencyTranscoding + root.latencySending
            },
            function(err) { console.warn("getLatencies error:", err) }
        )
    }

    function updateQuality() {
        controller.getInputQuality(
            function(result) {
                root.videoContinuity = Theme.normalizeNumber(result.videoContinuity, 0)
            },
            function(err) {}
        )
    }

    function updateFPS() {
        controller.getFPSFraction(
            function(result) {
                var num = Theme.normalizeNumber(result.num, 0)
                var den = Theme.normalizeNumber(result.den, 1)
                root.inputFPS = den > 0 ? num / den : 0
            },
            function(err) {}
        )
    }

    function doPing() {
        var start = Date.now()
        controller.ping("p",
            function() { root.pingRtt = Date.now() - start },
            function() {}
        )
    }

    // Player lag: decrement min lag between fetches
    function updatePlayerLag() {
        if (root.playerLagMin <= 0) {
            return
        }
        var now = Date.now()
        var tsDiff = now - root.playerLagLastUpdateAt
        root.playerLagMin -= tsDiff
        if (root.playerLagMin < 0) {
            root.playerLagMin = 0
        }
        root.playerLagLastUpdateAt = now
    }

    function fetchPlayerLag() {
        controller.playerGetLag("p1",
            function(lagReply) {
                var now = Date.now()
                var currentUnixNano = Math.floor(now * 1000000)
                var replyUnixNano = lagReply.replyUnixNano > lagReply.requestUnixNano
                    ? lagReply.replyUnixNano : lagReply.requestUnixNano
                var couldBeConsumedU = currentUnixNano - replyUnixNano
                root.playerLagMin = (lagReply.lagU - couldBeConsumedU) / 1000000
                root.playerLagMax = lagReply.lagU / 1000000
                if (root.playerLagMin > root.playerLagMax) {
                    root.playerLagMin = root.playerLagMax
                }
                root.playerLagLastUpdateAt = now
            },
            function(err) {
                root.playerLagMin = -1
                root.playerLagMax = -1
            }
        )
    }

    function updateWiFiInfo() {
        var wifiInfo = platformInstance.getCurrentWiFiConnection()
        if (wifiInfo !== null && (wifiInfo.ssid !== "" || wifiInfo.bssid !== "")) {
            root.wifiSsid = wifiInfo.ssid
            root.wifiBssid = wifiInfo.bssid
            root.wifiRssi = wifiInfo.rssi
            return
        }
        root.wifiSsid = ""
        root.wifiBssid = ""
        root.wifiRssi = -32768
    }

    function updateChannelQualityInfo() {
        controller.getChannelQuality(
            function(channels) {
                root.channelQualities = channels || []
            },
            function(err) {}
        )
    }

    function formatDurationMs(durationMS) {
        if (durationMS < 0) return "N/A"
        if (durationMS < 200) return Math.round(durationMS) + " ms"
        var seconds = Math.floor(durationMS / 1000)
        var deciSeconds = Math.floor((durationMS % 1000) / 100)
        if (seconds < 60) return seconds + "." + deciSeconds + "s"
        var minutes = Math.floor(seconds / 60)
        seconds = seconds % 60
        return minutes + ":" + String(seconds).padStart(2, "0")
    }

    function channelQualityColor(quality) {
        if (quality < -33) return Theme.error
        if (quality < 0) return Theme.warning
        return Theme.success
    }

    function injectDiagnosticsSubtitles() {
        var currentDiagnostics = {
            "latencyPreTranscoding": Math.round(root.latencyPreTranscoding),
            "latencyTranscoding": Math.round(root.latencyTranscoding),
            "latencySending": Math.round(root.latencySending),
            "fpsInput": root.inputFPS <= 0 ? -1 : Math.round(root.inputFPS),
            "fpsOutput": root.outputFPS <= 0 ? -1 : Math.round(root.outputFPS),
            "bitrateInputVideo": Math.round(root.inputBitrate),
            "bitrateOutputVideo": Math.round(root.outputBitrate),
            "playerLagMin": Math.round(root.playerLagMin),
            "playerLagMax": Math.round(root.playerLagMax),
            "pingRtt": Math.round(root.pingRtt),
            "wifiSsid": root.wifiSsid,
            "wifiBssid": root.wifiBssid,
            "wifiRssi": root.wifiRssi,
            "channels": root.channelQualities.map(function(ch) { return ch.quality || 0 }),
            "viewersYoutube": root.viewersYoutube,
            "viewersTwitch": root.viewersTwitch,
            "viewersKick": root.viewersKick,
            "signal": platformInstance.signalStrength,
            "streamTime": root.streamUptimeSeconds,
            "cpuUtilization": platformInstance.cpuUtilization,
            "memoryUtilization": platformInstance.memoryUtilization,
            "temperatures": platformInstance.temperatures
        }

        // Only send changes (full state every 10th update)
        var msg = {}
        var hasChanges = false
        var isFullState = (root.diagnosticsUpdateCount % 10) === 0

        for (var key in currentDiagnostics) {
            if (key === "channels" || key === "temperatures") {
                if (isFullState || JSON.stringify(currentDiagnostics[key]) !== JSON.stringify(root.lastDiagnostics[key])) {
                    msg[key] = currentDiagnostics[key]
                    hasChanges = true
                }
                continue
            }
            if (isFullState || currentDiagnostics[key] !== root.lastDiagnostics[key]) {
                msg[key] = currentDiagnostics[key]
                hasChanges = true
            }
        }

        if (!hasChanges) {
            root.diagnosticsUpdateCount++
            return
        }

        root.diagnosticsUpdateCount++
        root.lastDiagnostics = currentDiagnostics

        controller.injectDiagnostics(msg,
            function() {},
            function(err) { console.warn("injectDiagnostics error:", err) }
        )
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        contentHeight: mainColumn.implicitHeight
        clip: true

        Column {
            id: mainColumn
            width: parent.width
            spacing: Theme.spacingMedium

            // Platform status row
            Row {
                spacing: Theme.spacingSmall
                width: parent.width

                Components.StatusBadge {
                    objectName: "twitchBadge"
                    label: "Twitch" + (root.viewersTwitch > 0 ? " (" + root.viewersTwitch + ")" : "")
                    statusColor: root.viewersTwitch > 0 ? Theme.twitch : Theme.textTertiary
                    active: root.viewersTwitch > 0
                }

                Components.StatusBadge {
                    objectName: "youtubeBadge"
                    label: "YouTube" + (root.viewersYoutube > 0 ? " (" + root.viewersYoutube + ")" : "")
                    statusColor: root.viewersYoutube > 0 ? Theme.youtube : Theme.textTertiary
                    active: root.viewersYoutube > 0
                }

                Components.StatusBadge {
                    objectName: "kickBadge"
                    label: "Kick" + (root.viewersKick > 0 ? " (" + root.viewersKick + ")" : "")
                    statusColor: root.viewersKick > 0 ? Theme.kick : Theme.textTertiary
                    active: root.viewersKick > 0
                }
            }

            // Stream uptime
            Components.GlassCard {
                width: parent.width
                implicitHeight: uptimeRow.implicitHeight + Theme.spacingLarge * 2
                visible: root.streamActive

                Row {
                    id: uptimeRow
                    anchors.fill: parent
                    spacing: Theme.spacingMedium

                    Components.StatusBadge {
                        objectName: "streamActiveBadge"
                        label: "LIVE"
                        statusColor: Theme.error
                        active: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Uptime: " + Theme.formatDuration(root.streamUptimeSeconds)
                        Accessible.name: "Uptime: " + Theme.formatDuration(root.streamUptimeSeconds)
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.Medium
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Metrics grid
            Text {
                text: "Stream Metrics"
                Accessible.name: "Stream Metrics"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            GridLayout {
                width: parent.width
                columns: 2
                rowSpacing: Theme.spacingSmall
                columnSpacing: Theme.spacingSmall

                Components.MetricTile {
                    objectName: "inputBitrateTile"
                    title: "Input Bitrate"
                    value: Theme.formatBandwidth(root.inputBitrate)
                    numericValue: root.inputBitrate
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "outputBitrateTile"
                    title: "Output Bitrate"
                    value: Theme.formatBandwidth(root.outputBitrate)
                    numericValue: root.outputBitrate
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "latencyTile"
                    title: "Video Latency"
                    value: Theme.formatLatency(root.videoLatency)
                    numericValue: root.videoLatency
                    warningThreshold: 100000
                    criticalThreshold: 500000
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "fpsTile"
                    title: "Input FPS"
                    value: root.inputFPS > 0 ? root.inputFPS.toFixed(1) : "--"
                    unit: "fps"
                    numericValue: root.inputFPS
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "pingTile"
                    title: "Ping RTT"
                    value: root.pingRtt > 0 ? root.pingRtt.toFixed(0) : "--"
                    unit: "ms"
                    numericValue: root.pingRtt
                    warningThreshold: 100
                    criticalThreshold: 500
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "qualityTile"
                    title: "Continuity"
                    value: root.videoContinuity > 0 ? (root.videoContinuity * 100).toFixed(1) : "--"
                    unit: "%"
                    numericValue: (1 - root.videoContinuity) * 100
                    warningThreshold: 5
                    criticalThreshold: 20
                    Layout.fillWidth: true
                }
            }

            // System resources
            Text {
                text: "System"
                Accessible.name: "System"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            GridLayout {
                width: parent.width
                columns: 2
                rowSpacing: Theme.spacingSmall
                columnSpacing: Theme.spacingSmall

                Components.MetricTile {
                    objectName: "cpuTile"
                    title: "CPU"
                    value: platformInstance.cpuUtilization.toFixed(0)
                    unit: "%"
                    numericValue: platformInstance.cpuUtilization
                    warningThreshold: 70
                    criticalThreshold: 90
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "memoryTile"
                    title: "Memory"
                    value: platformInstance.memoryUtilization.toFixed(0)
                    unit: "%"
                    numericValue: platformInstance.memoryUtilization
                    warningThreshold: 80
                    criticalThreshold: 95
                    Layout.fillWidth: true
                }
            }

            // Thermal zones section (collapsible)
            Rectangle {
                id: thermalHeader
                width: parent.width
                height: thermalHeaderRow.implicitHeight + Theme.spacingSmall * 2
                radius: Theme.glassRadius
                color: {
                    var all = platformInstance.temperatures || []
                    if (all.length === 0) return Theme.surfaceColor
                    var worst = Theme.success
                    for (var i = 0; i < all.length; i++) {
                        var t = (all[i].type || "").toLowerCase()
                        var c = Theme.temperatureColor(all[i].temp,
                            (t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1) ? "battery"
                            : (t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1 || t.indexOf("soc") !== -1) ? "cpu"
                            : "skin")
                        if (c === Theme.error) { worst = Theme.error; break }
                        if (c !== Theme.success) worst = c
                    }
                    return Qt.rgba(worst.r, worst.g, worst.b, 0.15)
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                property bool expanded: false
                visible: (platformInstance.temperatures || []).length > 0

                Row {
                    id: thermalHeaderRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    spacing: Theme.spacingSmall

                    Text {
                        text: thermalHeader.expanded ? "\u25BC" : "\u25B6"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Thermal Zones (" + (platformInstance.temperatures || []).length + ")"
                        font.pixelSize: Theme.fontLarge
                        font.weight: Font.Medium
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: thermalHeader.expanded = !thermalHeader.expanded
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingTiny
                visible: thermalHeader.expanded

                Repeater {
                    model: platformInstance.temperatures || []
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        spacing: Theme.spacingSmall

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: {
                                var t = (modelData.type || "").toLowerCase()
                                var sensor = (t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1) ? "battery"
                                    : (t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1
                                       || t.indexOf("soc") !== -1 || t.indexOf("tsens") !== -1) ? "cpu"
                                    : "skin"
                                return Theme.temperatureColor(modelData.temp, sensor)
                            }
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: Math.round(modelData.temp) + "\u00B0C"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Bold
                            color: {
                                var t = (modelData.type || "").toLowerCase()
                                var sensor = (t.indexOf("batt") !== -1 || t.indexOf("bms") !== -1) ? "battery"
                                    : (t.indexOf("cpu") !== -1 || t.indexOf("gpu") !== -1
                                       || t.indexOf("soc") !== -1 || t.indexOf("tsens") !== -1) ? "cpu"
                                    : "skin"
                                return Theme.temperatureColor(modelData.temp, sensor)
                            }
                            width: 50
                        }

                        Text {
                            text: modelData.type || "unknown"
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                            elide: Text.ElideRight
                            width: parent.width - 80
                        }
                    }
                }
            }

            // Diagnostics section
            Text {
                text: "Diagnostics"
                Accessible.name: "Diagnostics"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            GridLayout {
                width: parent.width
                columns: 2
                rowSpacing: Theme.spacingSmall
                columnSpacing: Theme.spacingSmall

                Components.MetricTile {
                    objectName: "signalStrengthTile"
                    title: "Signal"
                    value: platformInstance.signalStrength > 0 ? platformInstance.signalStrength.toString() : "--"
                    unit: "dBm"
                    numericValue: Math.abs(platformInstance.signalStrength)
                    warningThreshold: 70
                    criticalThreshold: 85
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "viewersTotalTile"
                    title: "Total Viewers"
                    value: (root.viewersTwitch + root.viewersYoutube + root.viewersKick).toString()
                    numericValue: root.viewersTwitch + root.viewersYoutube + root.viewersKick
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "playerLagTile"
                    title: "Player Lag"
                    value: root.playerLagMin >= 0
                        ? root.formatDurationMs(root.playerLagMin) + " / " + root.formatDurationMs(root.playerLagMax)
                        : "--"
                    unit: ""
                    numericValue: root.playerLagMin >= 0 ? root.playerLagMin : 0
                    warningThreshold: 5000
                    criticalThreshold: 15000
                    Layout.fillWidth: true
                }

                Components.MetricTile {
                    objectName: "outputFpsTile"
                    title: "Output FPS"
                    value: root.outputFPS > 0 ? root.outputFPS.toFixed(1) : "--"
                    unit: "fps"
                    numericValue: root.outputFPS
                    Layout.fillWidth: true
                }
            }

            // WiFi info section
            Text {
                text: "WiFi"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
                visible: root.wifiSsid !== "" || root.wifiBssid !== ""
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: wifiColumn.implicitHeight + Theme.spacingMedium * 2
                visible: root.wifiSsid !== "" || root.wifiBssid !== ""

                Column {
                    id: wifiColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSmall
                    spacing: Theme.spacingTiny

                    Row {
                        spacing: Theme.spacingSmall
                        Text {
                            text: "SSID:"
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                        }
                        Text {
                            text: root.wifiSsid || "(hidden)"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Medium
                            color: Theme.textPrimary
                        }
                    }
                    Row {
                        spacing: Theme.spacingSmall
                        Text {
                            text: "BSSID:"
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                        }
                        Text {
                            text: root.wifiBssid || "--"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Medium
                            color: Theme.textPrimary
                        }
                    }
                    Row {
                        spacing: Theme.spacingSmall
                        Text {
                            text: "RSSI:"
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                        }
                        Text {
                            text: root.wifiRssi > -32768 ? root.wifiRssi + " dBm" : "--"
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Medium
                            color: {
                                if (root.wifiRssi >= -50) return Theme.success
                                if (root.wifiRssi >= -70) return Theme.warning
                                return Theme.error
                            }
                        }
                        Text {
                            text: {
                                if (root.wifiRssi <= -32768) return ""
                                // Approximate signal percentage: -30 dBm = 100%, -90 dBm = 0%
                                var pct = Math.max(0, Math.min(100, (root.wifiRssi + 90) * 100 / 60))
                                return "(" + Math.round(pct) + "%)"
                            }
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textTertiary
                        }
                    }
                }
            }

            // Channel quality section
            Text {
                text: "Channel Quality"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
                visible: root.channelQualities.length > 0
            }

            Row {
                spacing: Theme.spacingSmall
                visible: root.channelQualities.length > 0

                Repeater {
                    model: root.channelQualities
                    delegate: Components.GlassCard {
                        required property var modelData
                        required property int index
                        width: Math.max(80, (mainColumn.width - Theme.spacingSmall * (root.channelQualities.length - 1)) / root.channelQualities.length)
                        implicitHeight: chQualCol.implicitHeight + Theme.spacingMedium * 2

                        Column {
                            id: chQualCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacingSmall
                            spacing: Theme.spacingTiny

                            Text {
                                text: modelData.label || "?"
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                            }
                            Text {
                                text: (modelData.quality || 0).toString()
                                font.pixelSize: Theme.fontHuge
                                font.weight: Font.Bold
                                color: root.channelQualityColor(modelData.quality || 0)
                            }
                        }
                    }
                }
            }
        }
    }
}
