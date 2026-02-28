import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "playersPage"
    Accessible.role: Accessible.Pane

    property var players: []

    function refreshPlayers() {
        controller.listStreamPlayers(
            function(result) { root.players = result },
            function(err) { console.warn("listStreamPlayers error:", err) }
        )
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshPlayers()
    }

    Component.onCompleted: refreshPlayers()

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: Theme.spacingMedium

            Text {
                text: "Stream Players"
                Accessible.name: "Stream Players"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 60
                visible: root.players.length === 0

                Text {
                    text: "No active players"
                    Accessible.name: "No active players"
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    anchors.centerIn: parent
                }
            }

            Repeater {
                model: root.players
                delegate: Components.GlassCard {
                    width: col.width
                    implicitHeight: playerCol.implicitHeight + Theme.spacingLarge * 2
                    hoverEnabled: true

                    Column {
                        id: playerCol
                        anchors.fill: parent
                        spacing: Theme.spacingTiny

                        Text {
                            text: modelData.title || "Untitled"
                            Accessible.name: modelData.title || "Untitled"
                            font.pixelSize: Theme.fontMedium
                            font.weight: Font.Medium
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: modelData.link || ""
                            Accessible.name: modelData.link || ""
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textTertiary
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                        Text {
                            text: Theme.formatDuration(modelData.position || 0) + " / " +
                                  Theme.formatDuration(modelData.length || 0)
                            Accessible.name: Theme.formatDuration(modelData.position || 0) + " / " +
                                  Theme.formatDuration(modelData.length || 0)
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                        }

                        // Player control buttons
                        Row {
                            spacing: Theme.spacingSmall
                            topPadding: Theme.spacingTiny

                            Components.GlassButton {
                                objectName: "playerPlayPauseBtn"
                                text: modelData.isPaused ? "\u25B6" : "\u23F8"
                                width: 40
                                onClicked: controller.playerSetPause(modelData.id, !modelData.isPaused, function(){}, function(err){ console.warn("playerSetPause error:", err) })
                            }
                            Components.GlassButton {
                                objectName: "playerStopBtn"
                                text: "\u23F9"
                                width: 40
                                onClicked: controller.playerStop(modelData.id, function(){}, function(err){ console.warn("playerStop error:", err) })
                            }
                            Components.GlassButton {
                                objectName: "playerCloseBtn"
                                text: "\u2716"
                                width: 40
                                accentColor: Theme.error
                                onClicked: controller.playerClose(modelData.id, function(){ root.refreshPlayers() }, function(err){ console.warn("playerClose error:", err) })
                            }
                        }
                    }
                }
            }

            // Open URL section
            Text {
                text: "Open URL"
                Accessible.name: "Open URL"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Row {
                width: parent.width
                spacing: Theme.spacingSmall

                Components.SearchField {
                    id: playerUrlInput
                    objectName: "playerUrlInput"
                    width: parent.width - openBtn.width - Theme.spacingSmall
                    placeholder: "Enter URL to play..."
                }

                Components.GlassButton {
                    id: openBtn
                    objectName: "playerOpenBtn"
                    text: "Open"
                    filled: true
                    onClicked: {
                        if (playerUrlInput.text.length > 0) {
                            var pid = root.players.length > 0 ? root.players[0].id : "default"
                            controller.playerOpen(pid, playerUrlInput.text,
                                function() { playerUrlInput.text = ""; root.refreshPlayers() },
                                function(err) { console.warn("playerOpen error:", err) }
                            )
                        }
                    }
                }
            }
        }
    }
}
