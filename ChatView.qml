import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtMultimedia
import QtTextToSpeech
import Platform

Item {
    id: chatView

    property alias model: chatMessagesModel
    property alias list: messagesList
    property alias atYEnd: messagesList.atYEnd

    Platform {
        id: platform
    }

    SoundEffect {
        id: soundAddChatMessage
        source: "audio/chat_message_add.wav"
    }

    TextToSpeech {
        id: tts
    }

    FontLoader {
        id: fontFreeSans
        source: "qrc:/qt/qml/WingOut/fonts/FreeSans.ttf"
    }

    Row {
        id: chatSettings
        height: ttsEnabled.height
        spacing: 16

        CheckBox {
            id: vibrationEnabled
            checked: true
            text: "vibrate"
        }
        CheckBox {
            id: simpleNicknamesEnabled
            text: "nick:simple"
        }
        CheckBox {
            id: ttsEnabled
            enabled: tts.state !== TextToSpeech.Error
            text: "TTS"
            onCheckedChanged: function() {
                if (!ttsEnabled.checked) {
                    tts.stop()
                }
            }
        }
        CheckBox {
            id: ttsTellUsernames
            enabled: ttsEnabled.checked
            text: "TTS:name"
        }
    }

    ListView {
        id: messagesList
        x: 0
        y: chatSettings.height
        width: parent.width
        height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        property int spacing: 5
        property bool userInteracting: false

        function scrollToBottom() {
            Qt.callLater(function () {
                messagesList.positionViewAtEnd();
                Qt.callLater(function () {
                    messagesList.positionViewAtEnd();
                    scrollToBottomTimer.start();
                });
            });
        }

        Timer {
            id: scrollToBottomTimer
            interval: 100; running: true; repeat: false
            onTriggered: {
                if (messagesList.userInteracting) {
                    return;
                }
                messagesList.positionViewAtEnd();
                Qt.callLater(function () {
                    messagesList.positionViewAtEnd();
                });
            }
        }

        Component.onCompleted: {
            messagesList.scrollToBottom();
        }
        onCountChanged: {
            if (messagesList.userInteracting) {
                return;
            }
            messagesList.scrollToBottom();
        }
        onHeightChanged: {
            if (messagesList.userInteracting) {
                return;
            }
            messagesList.scrollToBottom();
        }

        Connections {
            target: chatMessagesModel
            function onRowsInserted(parent, first, last) {
                var msg = chatMessagesModel.get(last);
                if (!msg.isLive) {
                    return;
                }
                if (!messagesList.userInteracting) {
                    messagesList.scrollToBottom();
                }
                switch(msg.username.toLowerCase()) {
                case "savedggbot":
                    return;
                case "botrix":
                    return;
                case "botrixoficial":
                    return;
                }
                if (vibrationEnabled.checked) {
                    platform.vibrate(500, true)
                }
                var text = msg.message
                text = text.replace(/<[^>]*>/g, "")
                text = text.replace(/https?:\/\/[^\s]+/g, "<HTTP-link>")
                if (ttsEnabled.checked && tts.state !== TextToSpeech.Error) {
                    if (ttsTellUsernames.checked) {
                        var username = msg.usernameReadable ? msg.usernameReadable : msg.username;
                        text = "from "+username+": "+text
                    }
                    tts.enqueue(text);
                } else {
                    soundAddChatMessage.play();
                }
            }
        }

        onDraggingChanged: {
            messagesList.userInteracting = moving || dragging;
        }

        onMovingChanged: {
            messagesList.userInteracting = moving || dragging;
        }

        Button {
            id: scrollToBottomBtn
            width: 96
            height: 96
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            visible: !parent.atYEnd

            background: Rectangle {
                color: "#2196F3"
                radius: width / 2
                border.color: "#1976D2"
                border.width: 2
            }

            contentItem: Item {
                anchors.centerIn: parent
                // Down Arrow Icon
                Canvas {
                    width: 48
                    height: 48
                    anchors.centerIn: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.beginPath();
                        ctx.moveTo(8, 16);
                        ctx.lineTo(24, 32);
                        ctx.lineTo(40, 16);
                        ctx.lineWidth = 5;
                        ctx.strokeStyle = "white";
                        ctx.stroke();
                    }
                }
            }

            onClicked: {
                messagesList.scrollToBottom();
            }
        }

        model: ListModel {
            id: chatMessagesModel
            ListElement {
                timestamp: "53"
                platformName: "twitch"
                eventType: 1
                username: "some-twitch-user"
                usernameReadable: "Some Twitch User"
                message: "message 1"
                messageFormatType: 0
                isTest: true
            }
            ListElement {
                timestamp: "59"
                eventType: 2
                platformName: "youtube"
                username: "some-youtube-user"
                usernameReadable: "Some YouTube User"
                message: "message 2"
                messageFormatType: 0
                isTest: true
            }
        }
        delegate: Row {
            id: row
            required property string timestamp
            required property string platformName
            required property int    eventType
            required property string username
            required property string usernameReadable
            required property string message
            required property int    messageFormatType
            required property bool   isTest
            spacing: ListView.view.spacing
            visible: !isTest || chatView.parent == null
            Text {
                color: "#ffffff"
                textFormat: Text.RichText
                text: "\u200E" + "<font color='" + row.platformNameToColor(row.platformName) + "'>" + row.timestamp + "</font> "+row.formatEventType(row.eventType)+" <font color='" + row.usernameToColor(row.username) + "'>" + row.formatUsername() + "</font> " + row.formatMessage(row.message, row.messageFormatType)
                wrapMode: Text.WordWrap
                font.family: fontFreeSans.name
                font.letterSpacing: 1
                font.pointSize: 20
                font.bold: true
                lineHeight: 1.2
                width: messagesList.width
            }

            function platformNameToColor(platformName): string {
                switch (platformName) {
                case "twitch":
                    return "#6441a5";
                case "youtube":
                    return "#ff0000";
                case "kick":
                    return "#00ff00";
                }
            }

            function usernameToColor(username): string {
                var hash = 0;
                for (var i = 0; i < username.length; i++) {
                    hash = username.charCodeAt(i) + ((hash << 5) - hash);
                    hash = hash & hash;
                }
                var h = Math.abs(hash) % 360;
                var s = 80 + (Math.abs(hash) % 20);
                var l = 60 + (Math.abs(hash) % 20);
                function hslToRgb(h, s, l) {
                    s /= 100;
                    l /= 100;
                    let c = (1 - Math.abs(2 * l - 1)) * s;
                    let x = c * (1 - Math.abs((h / 60) % 2 - 1));
                    let m = l - c / 2;
                    let r = 0, g = 0, b = 0;
                    if (h < 60) {
                        r = c;
                        g = x;
                        b = 0;
                    } else if (h < 120) {
                        r = x;
                        g = c;
                        b = 0;
                    } else if (h < 180) {
                        r = 0;
                        g = c;
                        b = x;
                    } else if (h < 240) {
                        r = 0;
                        g = x;
                        b = c;
                    } else if (h < 300) {
                        r = x;
                        g = 0;
                        b = c;
                    } else {
                        r = c;
                        g = 0;
                        b = x;
                    }
                    r = Math.round((r + m) * 255);
                    g = Math.round((g + m) * 255);
                    b = Math.round((b + m) * 255);
                    return [r, g, b];
                }
                var rgb = hslToRgb(h, s, l);
                function rgbToHex(r, g, b) {
                    return "#" + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1).toUpperCase();
                }
                return rgbToHex(rgb[0], rgb[1], rgb[2]);
            }

            function formatUsername() {
                if (!simpleNicknamesEnabled.checked) {
                    return username;
                }
                if (!row.usernameReadable) {
                    return username;
                }
                return row.usernameReadable;
            }

            function formatEventType(eventType) {
                switch(eventType) {
                case 0:
                    return "<font color='#ffffff'>undefined</font>"
                case 1:
                    return ""
                case 2:
                    return "<font color='#ff00ff'>cheer</font>"
                case 4:
                    return "<font color='#ffff00'>ad_break</font>"
                case 6:
                    return "<font color='#ff00ff'>follow</font>"
                case 256:
                    return "<font color='#00ff00'>stream_online</font>"
                case 257:
                    return "<font color='#ff0000'>stream_offline</font>"
                case 258:
                    return "<font color='#ff0000'>stream_info_update</font>"
                case 512:
                    return "<font color='#ff00ff'>sub_new</font>"
                case 513:
                    return "<font color='#ff00ff'>sub_renew</font>"
                case 514:
                    return "<font color='#ff00ff'>gifted_sub</font>"
                case 768:
                    return "<font color='#ff00ff'>raid</font>"
                case 769:
                    return "<font color='#ff00ff'>shoutout</font>"
                case 1024:
                    return "<font color='#ffff00'>ban</font>"
                case 1025:
                    return "<font color='#ffff00'>hold</font>"
                case 65535:
                    return "<font color='#ffffff'>other</font>"
                }
                return "<font color='#ffffff'>unknown_"+eventType+"</font>"
            }
            function escapeHtml(text) {
                return text
                    .replace(/&/g, "&amp;")
                    .replace(/</g, "&lt;")
                    .replace(/>/g, "&gt;")
                    .replace(/"/g, "&quot;")
                    .replace(/'/g, "&#39;");
            }

            function formatMessage(message, messageFormatType) {
                switch (messageFormatType) {
                case 1: // plain
                    return escapeHtml(message);
                case 3: // HTML
                    return message;
                default:
                    console.warn("Unknown messageFormatType: " + messageFormatType);
                    return escapeHtml(message);
                }
            }
        }
    }
}
