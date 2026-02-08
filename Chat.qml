pragma ComponentBehavior: Bound
/* This file implements the Chat page as a full-screen view with raid/shoutout actions. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    required property var root
    id: chatPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Chat")

    property string raidShoutoutStatus: ""
    property color raidShoutoutStatusColor: "#808080"
    property var platformCapabilities: ({})

    Component.onCompleted: fetchPlatformCapabilities()

    function fetchPlatformCapabilities() {
        var platforms = ["twitch", "youtube", "kick"];
        for (var i = 0; i < platforms.length; i++) {
            (function(platID) {
                chatPage.root.dxProducerClient.getBackendInfo(platID, function(reply) {
                    var caps = chatPage.platformCapabilities;
                    caps[platID] = reply.capabilities;
                    chatPage.platformCapabilities = caps;
                    chatView.platformCapabilities = chatPage.platformCapabilities;
                }, function(error) {
                    console.warn("getBackendInfo failed for", platID, error);
                }, chatPage.root.grpcCallOptions);
            })(platforms[i]);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Collapsible raid/shoutout action bar
        ColumnLayout {
            id: actionBar
            Layout.fillWidth: true
            spacing: 0
            visible: actionBarToggle.checked

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 8
                spacing: 8

                TextField {
                    id: targetChannelField
                    Layout.fillWidth: true
                    placeholderText: "Channel name"
                    font.pixelSize: 14
                }

                Button {
                    text: "Shoutout"
                    font.pixelSize: 12
                    enabled: targetChannelField.text.length > 0
                    onClicked: {
                        var channel = targetChannelField.text;
                        chatPage.root.fireMultiPlatformRPC("Shoutout",
                            function(platID, onOk, onErr) { chatPage.root.dxProducerClient.shoutout(platID, channel, onOk, onErr, chatPage.root.grpcCallOptions); },
                            function(t) { chatPage.raidShoutoutStatus = t; },
                            function(c) { chatPage.raidShoutoutStatusColor = c; });
                    }
                }

                Button {
                    text: "Raid"
                    font.pixelSize: 12
                    palette.button: "#CC0000"
                    palette.buttonText: "white"
                    enabled: targetChannelField.text.length > 0
                    onClicked: {
                        var channel = targetChannelField.text;
                        chatPage.root.fireMultiPlatformRPC("Raid",
                            function(platID, onOk, onErr) { chatPage.root.dxProducerClient.raidTo(platID, channel, onOk, onErr, chatPage.root.grpcCallOptions); },
                            function(t) { chatPage.raidShoutoutStatus = t; },
                            function(c) { chatPage.raidShoutoutStatusColor = c; });
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: 4
                text: chatPage.raidShoutoutStatus
                color: chatPage.raidShoutoutStatusColor
                font.pixelSize: 12
                visible: chatPage.raidShoutoutStatus.length > 0
            }
        }

        // Toggle button for the action bar
        ToolButton {
            id: actionBarToggle
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            checkable: true
            checked: false
            text: checked ? "Hide Actions" : "Raid / Shoutout"
            font.pixelSize: 12
        }

        ChatView {
            id: chatView
            root: chatPage.root
            model: chatPage.root.globalChatMessagesModel
            platformCapabilities: chatPage.platformCapabilities
            Layout.fillWidth: true
            Layout.fillHeight: true

            onRequestBanUser: function(platID, userID, reason, deadlineUnixMs) {
                console.log("Ban user:", platID, userID, reason, deadlineUnixMs);
                chatPage.root.dxProducerClient.banUser(platID, userID, reason, deadlineUnixMs,
                    function() { console.log("ban ok:", platID, userID); },
                    function(err) { console.warn("ban failed:", err); },
                    chatPage.root.grpcCallOptions);
            }
            onRequestRemoveChatMessage: function(platID, messageID) {
                console.log("Remove chat message:", platID, messageID);
                chatPage.root.dxProducerClient.removeChatMessage(platID, messageID,
                    function() { console.log("delete ok:", platID, messageID); },
                    function(err) { console.warn("delete failed:", err); },
                    chatPage.root.grpcCallOptions);
            }
        }
    }
}
