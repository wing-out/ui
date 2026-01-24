/* This file implements the Chat page as a full-screen view. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Page {
    id: chatPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Chat")

    ChatView {
        id: chatView
        model: globalChatMessagesModel
        anchors.fill: parent
    }
}
