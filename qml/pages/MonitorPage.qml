import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "monitorPage"
    Accessible.role: Accessible.Pane

    property bool isPlaying: false
    property bool isMuted: true
    property var sources: []
    property string selectedSource: ""
    property string sourceResolution: "--"
    property string sourceCodec: "--"
    property string sourceUrl: ""

    function refreshSources() {
        controller.listStreamSources(
            function(result) {
                root.sources = result
                if (result.length > 0 && root.selectedSource === "") {
                    root.selectedSource = result[0].id
                }
                // Update resolution/codec from selected source data
                for (var i = 0; i < result.length; i++) {
                    if (result[i].id === root.selectedSource) {
                        root.sourceResolution = result[i].resolution || "--"
                        root.sourceCodec = result[i].codec || "--"
                        root.sourceUrl = result[i].url || ""
                        break
                    }
                }
            },
            function(err) { console.warn("listStreamSources error:", err) }
        )
    }

    Component.onCompleted: refreshSources()

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshSources()
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
                text: "Stream Monitor"
                Accessible.name: "Stream Monitor"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            // Source selector
            Row {
                spacing: Theme.spacingSmall
                visible: root.sources.length > 1

                Text {
                    text: "Source:"
                    Accessible.name: "Source:"
                    font.pixelSize: Theme.fontSmall
                    color: Theme.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Repeater {
                    model: root.sources
                    Components.GlassButton {
                        objectName: "monitorSourceBtn_" + (modelData.id || index)
                        text: modelData.id || ("Source " + index)
                        filled: root.selectedSource === modelData.id
                        onClicked: {
                            root.selectedSource = modelData.id
                            root.refreshSources()
                        }
                    }
                }
            }

            // Video preview area
            Components.GlassCard {
                width: parent.width
                implicitHeight: width * 9 / 16

                Components.VideoPlayerRTMP {
                    id: videoPlayer
                    anchors.fill: parent
                    source: root.isPlaying && root.sourceUrl !== "" ? root.sourceUrl : ""
                    muted: root.isMuted

                    // Show placeholder when not playing
                    Text {
                        text: "No preview available"
                        Accessible.name: "No preview available"
                        font.pixelSize: Theme.fontMedium
                        color: Theme.textTertiary
                        anchors.centerIn: parent
                        visible: !root.isPlaying || root.sourceUrl === ""
                        z: 1
                    }
                }
            }

            // Playback controls
            Row {
                width: parent.width
                spacing: Theme.spacingSmall

                Components.GlassButton {
                    objectName: "monitorPlayPauseBtn"
                    text: root.isPlaying ? "\u23F8" : "\u25B6"
                    width: 60
                    onClicked: {
                        root.isPlaying = !root.isPlaying
                        if (root.isPlaying) {
                            videoPlayer.play()
                        } else {
                            videoPlayer.pause()
                        }
                    }
                }

                Components.GlassButton {
                    objectName: "monitorStopBtn"
                    text: "\u23F9"
                    width: 60
                    onClicked: {
                        root.isPlaying = false
                        videoPlayer.stop()
                    }
                }

                Item { width: 10; height: 1 }

                Components.GlassButton {
                    objectName: "monitorMuteBtn"
                    text: root.isMuted ? "\uD83D\uDD07" : "\uD83D\uDD0A"
                    width: 60
                    onClicked: root.isMuted = !root.isMuted
                }
            }

            // Stream info
            Text {
                text: "Stream Info"
                Accessible.name: "Stream Info"
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
                    objectName: "monitorResolutionTile"
                    title: "Resolution"
                    value: root.sourceResolution
                    Layout.fillWidth: true
                }
                Components.MetricTile {
                    objectName: "monitorCodecTile"
                    title: "Codec"
                    value: root.sourceCodec
                    Layout.fillWidth: true
                }
            }

            // Selected source details
            Text {
                text: "Selected Source: " + (root.selectedSource !== "" ? root.selectedSource : "none")
                Accessible.name: "Selected Source: " + (root.selectedSource !== "" ? root.selectedSource : "none")
                font.pixelSize: Theme.fontSmall
                color: Theme.textSecondary
                topPadding: Theme.spacingSmall
            }
        }
    }
}
