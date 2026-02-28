import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "profilesPage"
    Accessible.role: Accessible.Pane

    property var profiles: []
    property string activeProfile: ""

    function refreshProfiles() {
        controller.listProfiles(
            function(result) { root.profiles = result },
            function(err) { console.warn("listProfiles error:", err) }
        )
    }

    Component.onCompleted: refreshProfiles()

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refreshProfiles()
    }

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
                text: "Streaming Profiles"
                Accessible.name: "Streaming Profiles"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 60
                visible: root.profiles.length === 0

                Text {
                    text: "No profiles configured"
                    Accessible.name: "No profiles configured"
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    anchors.centerIn: parent
                }
            }

            Repeater {
                model: root.profiles
                delegate: Components.GlassCard {
                    width: col.width
                    implicitHeight: profCol.implicitHeight + Theme.spacingLarge * 2
                    hoverEnabled: true

                    Column {
                        id: profCol
                        anchors.fill: parent
                        spacing: Theme.spacingSmall

                        Row {
                            width: parent.width
                            spacing: Theme.spacingSmall

                            Text {
                                text: modelData.name || "Unnamed"
                                Accessible.name: modelData.name || "Unnamed"
                                font.pixelSize: Theme.fontMedium
                                font.weight: Font.Bold
                                color: Theme.textPrimary
                            }

                            Components.StatusBadge {
                                visible: root.activeProfile === (modelData.name || "")
                                label: "Active"
                                statusColor: Theme.success
                                active: true
                            }
                        }

                        Text {
                            text: modelData.description || ""
                            Accessible.name: modelData.description || ""
                            font.pixelSize: Theme.fontSmall
                            color: Theme.textSecondary
                            wrapMode: Text.Wrap
                            width: parent.width
                            visible: text !== ""
                        }

                        Row {
                            spacing: Theme.spacingSmall

                            Components.GlassButton {
                                objectName: "profileStartStopBtn"
                                text: root.activeProfile === (modelData.name || "") ? "Stop" : "Start"
                                filled: true
                                accentColor: root.activeProfile === (modelData.name || "") ?
                                    Theme.error : Theme.success
                                onClicked: {
                                    if (root.activeProfile === (modelData.name || "")) {
                                        // Stop on all platforms
                                        var stopPlatforms = ["twitch", "youtube", "kick"]
                                        for (var j = 0; j < stopPlatforms.length; j++) {
                                            controller.endStream(stopPlatforms[j],
                                                function() { root.activeProfile = "" },
                                                function(err) { console.warn("endStream error:", err) }
                                            )
                                        }
                                    } else {
                                        // Start on all platforms
                                        var startPlatforms = ["twitch", "youtube", "kick"]
                                        var pName = modelData.name
                                        for (var i = 0; i < startPlatforms.length; i++) {
                                            controller.startStream(startPlatforms[i], pName,
                                                function() { root.activeProfile = pName },
                                                function(err) { console.warn("startStream error:", err) }
                                            )
                                        }
                                    }
                                }
                            }

                            Components.GlassButton {
                                objectName: "profileApplyBtn"
                                text: "Apply"
                                onClicked: {
                                    controller.applyProfile(modelData.name,
                                        function() { console.log("Profile applied") },
                                        function(err) { console.warn("applyProfile error:", err) }
                                    )
                                }
                            }

                            Components.GlassButton {
                                objectName: "profileEditBtn"
                                text: "Edit"
                            }
                        }
                    }
                }
            }
        }
    }
}
