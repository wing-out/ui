import QtQuick
import QtQuick.Layouts
import QtMultimedia
import QtTextToSpeech
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "chatPage"
    Accessible.role: Accessible.Pane

    property var messages: ListModel {}
    property string platformFilter: ""
    property bool ttsEnabled: false
    property bool ttsUsernames: false
    property bool vibrateEnabled: false
    property bool soundEnabled: true

    // Bot usernames to filter out from notifications
    property var botUsernames: ["savedggbot", "botrix", "botrixoficial", "nightbot", "streamelements"]

    function usernameColor(name) {
        var hash = 0;
        for (var i = 0; i < name.length; i++) {
            hash = name.charCodeAt(i) + ((hash << 5) - hash);
        }
        var h = Math.abs(hash) % 360;
        return Qt.hsla(h / 360.0, 0.7, 0.6, 1.0);
    }

    function isBot(userName) {
        if (!userName) return false;
        return botUsernames.indexOf(userName.toLowerCase()) >= 0;
    }

    TextToSpeech {
        id: tts
    }

    SoundEffect {
        id: chatSound
        source: "qrc:/audio/chat_message_add.wav"
    }

    // Subscribe to chat messages when connected
    Component.onCompleted: {
        controller.subscribeToChatMessages();
    }

    Connections {
        target: controller
        function onChatMessageReceived(message) {
            var userName = message.userName || "";
            var displayName = (message.user && message.user.nameReadable) ? message.user.nameReadable : userName;
            var text = message.text || "";
            var platform = message.platform || "";

            root.messages.append({
                "messageId": message.messageId || "",
                "platform": platform,
                "userName": userName,
                "displayName": displayName,
                "message": text,
                "timestamp": message.timestamp || 0,
                "eventType": message.eventType || 0
            });

            // Skip bots for notifications
            if (root.isBot(userName)) {
                return;
            }

            // Strip HTML tags and URLs for TTS
            var cleanText = text.replace(/<[^>]*>/g, "");
            cleanText = cleanText.replace(/https?:\/\/[^\s]+/g, "<HTTP-link>");

            if (root.ttsEnabled && tts.state !== TextToSpeech.Error) {
                var ttsText = cleanText;
                if (root.ttsUsernames) {
                    var speakName = displayName || userName;
                    ttsText = "from " + speakName + ": " + ttsText;
                }
                tts.enqueue(ttsText);
            } else if (root.soundEnabled) {
                chatSound.play();
            }

            if (root.vibrateEnabled) {
                platformInstance.vibrate(500, true);
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingMedium

        // Platform filter row
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.GlassButton {
                objectName: "chatFilterAll"
                text: "All"
                filled: root.platformFilter === ""
                onClicked: root.platformFilter = ""
            }
            Components.GlassButton {
                objectName: "chatFilterTwitch"
                text: "Twitch"
                filled: root.platformFilter === "twitch"
                accentColor: Theme.twitch
                onClicked: root.platformFilter = "twitch"
            }
            Components.GlassButton {
                objectName: "chatFilterYouTube"
                text: "YouTube"
                filled: root.platformFilter === "youtube"
                accentColor: Theme.youtube
                onClicked: root.platformFilter = "youtube"
            }
            Components.GlassButton {
                objectName: "chatFilterKick"
                text: "Kick"
                filled: root.platformFilter === "kick"
                accentColor: Theme.kick
                onClicked: root.platformFilter = "kick"
            }
        }

        // Toggle controls
        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.GlassButton {
                objectName: "ttsToggle"
                text: root.ttsEnabled ? "TTS ON" : "TTS OFF"
                filled: root.ttsEnabled
                accentColor: Theme.accentSecondary
                onClicked: {
                    root.ttsEnabled = !root.ttsEnabled;
                    if (!root.ttsEnabled) {
                        tts.stop();
                    }
                }
            }

            Components.GlassButton {
                objectName: "ttsUsernamesToggle"
                text: root.ttsUsernames ? "TTS:name ON" : "TTS:name OFF"
                filled: root.ttsUsernames
                enabled: root.ttsEnabled
                accentColor: Theme.accentSecondary
                onClicked: root.ttsUsernames = !root.ttsUsernames
            }

            Components.GlassButton {
                objectName: "vibrateToggle"
                text: root.vibrateEnabled ? "Vibrate ON" : "Vibrate OFF"
                filled: root.vibrateEnabled
                onClicked: root.vibrateEnabled = !root.vibrateEnabled
            }

            Components.GlassButton {
                objectName: "soundToggle"
                text: root.soundEnabled ? "Sound ON" : "Sound OFF"
                filled: root.soundEnabled
                onClicked: root.soundEnabled = !root.soundEnabled
            }
        }

        // Chat messages — fills remaining space
        ListView {
            id: chatList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.messages
            clip: true
            spacing: Theme.spacingTiny
            verticalLayoutDirection: ListView.BottomToTop

            delegate: Components.GlassCard {
                width: chatList.width
                implicitHeight: msgCol.implicitHeight + Theme.spacingMedium * 2
                visible: root.platformFilter === "" || model.platform === root.platformFilter

                Column {
                    id: msgCol
                    anchors.fill: parent
                    spacing: Theme.spacingTiny

                    Row {
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
                    }

                    Text {
                        text: model.message || ""
                        font.pixelSize: Theme.fontMedium
                        color: Theme.textPrimary
                        wrapMode: Text.Wrap
                        width: parent.width
                    }
                }
            }
        }

        // Message sending input — pinned at bottom
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.SearchField {
                id: chatInput
                objectName: "chatInput"
                width: parent.width - sendBtn.width - Theme.spacingSmall
                placeholder: "Type a message..."
            }

            Components.GlassButton {
                id: sendBtn
                objectName: "chatSendButton"
                text: "Send"
                filled: true
                width: 80
                onClicked: {
                    if (chatInput.text.length > 0) {
                        var platform = root.platformFilter !== "" ? root.platformFilter : "twitch"
                        controller.sendChatMessage(platform, chatInput.text,
                            function() { chatInput.text = "" },
                            function(err) { console.warn("sendChatMessage error:", err) }
                        )
                    }
                }
            }
        }
    }
}
