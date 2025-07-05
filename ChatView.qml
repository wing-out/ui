import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtMultimedia
import QtTextToSpeech
import Platform

Item {
    id: chatView

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

    function scrollToBottom() {
        Qt.callLater(function () {
            messagesList.positionViewAtEnd();
            Qt.callLater(function () {
                messagesList.positionViewAtEnd();
            });
        });
    }

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
        model: ListModel {
            id: chatMessagesModel
            ListElement {
                timestamp: "53"
                platformName: "twitch"
                username: "some-twitch-user"
                message: "message 1"
                isTest: true
            }
            ListElement {
                timestamp: "59"
                platformName: "youtube"
                username: "some-youtube-user"
                message: "message 2"
                isTest: true
            }
        }
        delegate: Row {
            spacing: messagesList.spacing
            visible: !isTest || chatView.parent == null
            Text {
                color: "#ffffff"
                text: "<font color='" + platformNameToColor(platformName) + "'>" + timestamp + "</font> <font color='" + usernameToColor(username) + "'>" + username + "</font> " + message
                wrapMode: Text.WordWrap
                font.pointSize: 20
                font.bold: true
                width: messagesList.width
            }
        }
        property int spacing: 5
        property bool userInteracting: false
        Component.onCompleted: {
            chatView.scrollToBottom();
        }
        onCountChanged: {
            if (userInteracting) {
                return;
            }
            chatView.scrollToBottom();
        }
        onHeightChanged: {
            if (userInteracting) {
                return;
            }
            chatView.scrollToBottom();
        }

        Connections {
            target: chatMessagesModel
            function onRowsInserted(parent, first, last) {
                var msg = chatMessagesModel.get(last);
                if (!msg.isLive) {
                    return;
                }
                if (!messagesList.userInteracting) {
                    chatView.scrollToBottom();
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
                text = text.replace(/https?:\/\/[^\s]+/g, "<HTTP-link>")
                if (ttsEnabled.checked && tts.state !== TextToSpeech.Error) {
                    if (ttsTellUsernames.checked) {
                        text = "from "+msg.username+": "+text
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
                chatView.scrollToBottom();
            }
        }
    }
}
