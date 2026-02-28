import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller

    Accessible.name: "restreamsPage"
    Accessible.role: Accessible.Pane

    property var forwards: []
    property bool showAddForwardDialog: false
    property string newSourceId: ""
    property string newSinkId: ""

    function refreshForwards() {
        controller.listStreamForwards(
            function(result) { root.forwards = result },
            function(err) { console.warn("listStreamForwards error:", err) }
        )
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshForwards()
    }

    Component.onCompleted: refreshForwards()

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
                text: "Stream Forwards"
                Accessible.name: "Stream Forwards"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 60
                visible: root.forwards.length === 0

                Text {
                    text: "No active stream forwards"
                    Accessible.name: "No active stream forwards"
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    anchors.centerIn: parent
                }
            }

            Repeater {
                model: root.forwards
                delegate: Components.GlassCard {
                    width: col.width
                    implicitHeight: fwdCol.implicitHeight + Theme.spacingLarge * 2
                    hoverEnabled: true

                    Column {
                        id: fwdCol
                        anchors.fill: parent
                        spacing: Theme.spacingSmall

                        Row {
                            spacing: Theme.spacingMedium
                            width: parent.width

                            Column {
                                width: parent.width - fwdStatusBadge.width - Theme.spacingMedium
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: (modelData.sourceId || "?") + " \u2192 " + (modelData.sinkId || "?")
                                    Accessible.name: (modelData.sourceId || "?") + " → " + (modelData.sinkId || "?")
                                    font.pixelSize: Theme.fontMedium
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    text: modelData.sinkType || "custom"
                                    Accessible.name: modelData.sinkType || "custom"
                                    font.pixelSize: Theme.fontSmall
                                    color: Theme.textTertiary
                                }
                            }

                            Components.StatusBadge {
                                id: fwdStatusBadge
                                label: modelData.enabled ? "Active" : "Disabled"
                                statusColor: modelData.enabled ? Theme.success : Theme.textTertiary
                                active: modelData.enabled
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            spacing: Theme.spacingSmall

                            Components.GlassButton {
                                objectName: "forwardToggleBtn"
                                text: modelData.enabled ? "Disable" : "Enable"
                                filled: !modelData.enabled
                                accentColor: modelData.enabled ? Theme.warning : Theme.success
                                onClicked: {
                                    controller.updateStreamForward(
                                        modelData.sourceId, modelData.sinkId, !modelData.enabled,
                                        function() { root.refreshForwards() },
                                        function(err) { console.warn("updateStreamForward error:", err) }
                                    )
                                }
                            }

                            Components.GlassButton {
                                objectName: "forwardRemoveBtn"
                                text: "Remove"
                                accentColor: Theme.error
                                onClicked: {
                                    controller.removeStreamForward(modelData.sourceId, modelData.sinkId,
                                        function() { root.refreshForwards() },
                                        function(err) { console.warn("removeStreamForward error:", err) }
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Add Forward button
            Components.GlassButton {
                objectName: "addForwardButton"
                text: root.showAddForwardDialog ? "Cancel" : "Add Forward"
                filled: !root.showAddForwardDialog
                width: parent.width
                onClicked: {
                    root.showAddForwardDialog = !root.showAddForwardDialog
                    if (!root.showAddForwardDialog) {
                        root.newSourceId = ""
                        root.newSinkId = ""
                    }
                }
            }

            // Add Forward dialog
            Components.GlassCard {
                width: parent.width
                implicitHeight: addFwdCol.implicitHeight + Theme.spacingLarge * 2
                visible: root.showAddForwardDialog

                Column {
                    id: addFwdCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Text {
                        text: "Source ID"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: fwdSourceField
                        objectName: "fwdSourceField"
                        width: parent.width
                        placeholder: "e.g. cam1"
                        text: root.newSourceId
                        onTextChanged: root.newSourceId = text
                    }

                    Text {
                        text: "Sink ID"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: fwdSinkField
                        objectName: "fwdSinkField"
                        width: parent.width
                        placeholder: "e.g. twitch-out"
                        text: root.newSinkId
                        onTextChanged: root.newSinkId = text
                    }

                    Components.GlassButton {
                        objectName: "confirmAddForwardButton"
                        text: "Add"
                        filled: true
                        width: parent.width
                        enabled: root.newSourceId.length > 0 && root.newSinkId.length > 0
                        onClicked: {
                            controller.addStreamForward(root.newSourceId, root.newSinkId, true,
                                function() {
                                    root.newSourceId = ""
                                    root.newSinkId = ""
                                    root.showAddForwardDialog = false
                                    root.refreshForwards()
                                },
                                function(err) { console.warn("addStreamForward error:", err) }
                            )
                        }
                    }
                }
            }
        }
    }
}
