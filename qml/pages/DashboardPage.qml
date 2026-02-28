import QtQuick
import QtQuick.Layouts
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
                    var transcoding = Theme.normalizeNumber(result.videoTranscoding, 0)
                    var sending = Theme.normalizeNumber(result.videoSending, 0)
                    root.videoLatency = transcoding + sending
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
                "message": text
            })
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

        // Compact metrics bar
        Row {
            objectName: "dashboardCompactMetrics"
            Layout.fillWidth: true
            spacing: Theme.spacingMedium

            Text {
                text: Theme.formatBandwidth(root.inputBitrate)
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Medium
                color: Theme.textPrimary
                Accessible.name: "dashboardBitrate"
            }

            Text {
                text: Theme.formatLatency(root.videoLatency)
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Medium
                color: Theme.textPrimary
                Accessible.name: "dashboardLatency"
            }

            Text {
                text: root.inputFPS > 0 ? root.inputFPS.toFixed(1) + " fps" : "-- fps"
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Medium
                color: Theme.textPrimary
                Accessible.name: "dashboardFps"
            }

            Text {
                text: root.pingRtt > 0 ? root.pingRtt.toFixed(0) + " ms RTT" : "-- ms RTT"
                font.pixelSize: Theme.fontSmall
                font.weight: Font.Medium
                color: Theme.textPrimary
                Accessible.name: "dashboardPing"
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
