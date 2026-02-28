import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "camerasPage"
    Accessible.role: Accessible.Pane

    property var sources: []
    property var servers: []
    property bool showAddSourceDialog: false
    property string newSourceId: ""
    property string newSourceUrl: ""

    function refreshSources() {
        controller.listStreamSources(
            function(result) { root.sources = result },
            function(err) { console.warn("listStreamSources error:", err) }
        )
    }

    function refreshServers() {
        controller.listStreamServers(
            function(result) { root.servers = result },
            function(err) { console.warn("listStreamServers error:", err) }
        )
    }

    Component.onCompleted: { refreshSources(); refreshServers() }

    Timer {
        id: sourcesPollTimer
        interval: 2000
        running: true
        repeat: true
        onTriggered: { root.refreshSources(); root.refreshServers() }
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
                text: "Stream Sources"
                Accessible.name: "Stream Sources"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: emptyText.implicitHeight + Theme.spacingLarge * 2
                visible: root.sources.length === 0

                Text {
                    id: emptyText
                    text: "No cameras configured.\nAdd a stream source to get started."
                    Accessible.name: "No cameras configured. Add a stream source to get started."
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    anchors.centerIn: parent
                }
            }

            Repeater {
                model: root.sources
                delegate: Components.GlassCard {
                    width: col.width
                    implicitHeight: sourceRow.implicitHeight + Theme.spacingLarge * 2
                    hoverEnabled: true

                    Row {
                        id: sourceRow
                        anchors.fill: parent
                        spacing: Theme.spacingMedium

                        Rectangle {
                            width: 40; height: 40
                            radius: 8
                            color: Theme.accentPrimary
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "\uD83C\uDFA5"
                                font.pixelSize: 20
                                anchors.centerIn: parent
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 40 - removeSourceBtn.width - Theme.spacingMedium * 3

                            Text {
                                text: modelData.id || "Camera"
                                Accessible.name: modelData.id || "Camera"
                                font.pixelSize: Theme.fontMedium
                                color: Theme.textPrimary
                            }
                            Text {
                                text: modelData.url || ""
                                Accessible.name: modelData.url || ""
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                                elide: Text.ElideMiddle
                                width: parent.width
                            }
                            Row {
                                spacing: Theme.spacingSmall
                                Components.StatusBadge {
                                    label: modelData.isActive ? "Active" : "Inactive"
                                    statusColor: modelData.isActive ? Theme.success : Theme.textTertiary
                                    active: modelData.isActive || false
                                }
                                Components.StatusBadge {
                                    visible: modelData.isSuppressed || false
                                    label: "Suppressed"
                                    statusColor: Theme.warning
                                }
                            }
                        }

                        Components.GlassButton {
                            id: removeSourceBtn
                            objectName: "removeSourceBtn"
                            text: "Remove"
                            accentColor: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                controller.removeStreamSource(modelData.id,
                                    function() { root.refreshSources() },
                                    function(err) { console.warn("removeStreamSource error:", err) }
                                )
                            }
                        }
                    }
                }
            }

            // Add Source button
            Components.GlassButton {
                objectName: "addSourceButton"
                text: root.showAddSourceDialog ? "Cancel" : "Add Source"
                filled: !root.showAddSourceDialog
                width: parent.width
                onClicked: {
                    root.showAddSourceDialog = !root.showAddSourceDialog
                    if (!root.showAddSourceDialog) {
                        root.newSourceId = ""
                        root.newSourceUrl = ""
                    }
                }
            }

            // Add Source dialog
            Components.GlassCard {
                width: parent.width
                implicitHeight: addSourceCol.implicitHeight + Theme.spacingLarge * 2
                visible: root.showAddSourceDialog

                Column {
                    id: addSourceCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Text {
                        text: "Source ID"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: sourceIdField
                        objectName: "sourceIdField"
                        width: parent.width
                        placeholder: "e.g. cam1"
                        text: root.newSourceId
                        onTextChanged: root.newSourceId = text
                    }

                    Text {
                        text: "Source URL"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: sourceUrlField
                        objectName: "sourceUrlField"
                        width: parent.width
                        placeholder: "rtmp://... or srt://..."
                        text: root.newSourceUrl
                        onTextChanged: root.newSourceUrl = text
                    }

                    Components.GlassButton {
                        objectName: "confirmAddSourceButton"
                        text: "Add"
                        filled: true
                        width: parent.width
                        enabled: root.newSourceId.length > 0 && root.newSourceUrl.length > 0
                        onClicked: {
                            controller.addStreamSource(root.newSourceId, root.newSourceUrl,
                                function() {
                                    root.newSourceId = ""
                                    root.newSourceUrl = ""
                                    root.showAddSourceDialog = false
                                    root.refreshSources()
                                },
                                function(err) { console.warn("addStreamSource error:", err) }
                            )
                        }
                    }
                }
            }

            // Stream Servers section
            Text {
                text: "Stream Servers"
                Accessible.name: "Stream Servers"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 60
                visible: root.servers.length === 0

                Text {
                    text: "No stream servers running"
                    Accessible.name: "No stream servers running"
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    anchors.centerIn: parent
                }
            }

            Repeater {
                model: root.servers
                delegate: Components.GlassCard {
                    width: col.width
                    implicitHeight: serverRow.implicitHeight + Theme.spacingLarge * 2
                    hoverEnabled: true

                    Row {
                        id: serverRow
                        anchors.fill: parent
                        spacing: Theme.spacingMedium

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - stopServerBtn.width - Theme.spacingMedium

                            Text {
                                text: modelData.id || "Server"
                                Accessible.name: modelData.id || "Server"
                                font.pixelSize: Theme.fontMedium
                                font.weight: Font.Medium
                                color: Theme.textPrimary
                            }
                            Text {
                                text: modelData.listenAddr || ""
                                Accessible.name: modelData.listenAddr || ""
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textSecondary
                            }
                            Text {
                                text: "Type: " + (modelData.type || "unknown")
                                Accessible.name: "Type: " + (modelData.type || "unknown")
                                font.pixelSize: Theme.fontSmall
                                color: Theme.textTertiary
                            }
                        }

                        Components.GlassButton {
                            id: stopServerBtn
                            objectName: "stopServerBtn"
                            text: "Stop"
                            accentColor: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                controller.stopStreamServer(modelData.id,
                                    function() { root.refreshServers() },
                                    function(err) { console.warn("stopStreamServer error:", err) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
