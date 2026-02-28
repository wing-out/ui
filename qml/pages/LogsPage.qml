import QtQuick
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root

    Accessible.name: "logsPage"
    Accessible.role: Accessible.Pane

    required property var logModel
    property bool filterErrors: false

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        // Filter row
        Row {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Components.GlassButton {
                objectName: "logsFilterAll"
                text: "All (" + root.logModel.count + ")"
                filled: !root.filterErrors
                onClicked: root.filterErrors = false
            }
            Components.GlassButton {
                objectName: "logsFilterErrors"
                text: "Errors (" + root.logModel.errorCount + ")"
                filled: root.filterErrors
                accentColor: Theme.error
                onClicked: root.filterErrors = true
            }

            Item { width: 1; Layout.fillWidth: true }

            Components.GlassButton {
                objectName: "logsClear"
                text: "Clear"
                onClicked: root.logModel.clearAll()
            }
        }

        // Log list
        ListView {
            id: logList
            objectName: "logsList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            verticalLayoutDirection: ListView.BottomToTop
            model: root.logModel

            delegate: Item {
                width: logList.width
                visible: !root.filterErrors || model.isError
                implicitHeight: visible ? logRow.implicitHeight + Theme.spacingTiny : 0

                Row {
                    id: logRow
                    width: parent.width
                    spacing: Theme.spacingSmall
                    visible: parent.visible

                    Rectangle {
                        width: 3
                        height: logMsg.implicitHeight
                        radius: 1
                        color: model.isError ? Theme.error : Theme.textTertiary
                    }

                    Text {
                        text: model.lastTime !== "" ? model.time + "-" + model.lastTime : model.time
                        font.pixelSize: Theme.fontTiny
                        font.family: "monospace"
                        color: Theme.textTertiary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        visible: model.repeatCount > 1
                        text: "x" + model.repeatCount
                        font.pixelSize: Theme.fontTiny
                        font.weight: Font.Bold
                        color: Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        id: logMsg
                        text: model.message
                        font.pixelSize: Theme.fontSmall
                        color: model.isError ? Theme.error : Theme.textPrimary
                        wrapMode: Text.Wrap
                        width: parent.width - x
                    }
                }
            }
        }
    }
}
