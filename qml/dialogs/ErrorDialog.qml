import QtQuick
import "../components" as Components
import WingOut

Rectangle {
    id: root

    Accessible.name: "errorDialog"
    Accessible.description: root.errorMessage
    Accessible.role: Accessible.AlertMessage

    property string errorMessage: ""
    property int autoHideMs: 5000

    signal dismissed()

    visible: errorMessage !== ""
    color: "transparent"

    Components.GlassCard {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacingLarge
        width: Math.min(parent.width - Theme.spacingLarge * 2, 500)
        height: errorText.implicitHeight + Theme.spacingLarge * 2
        borderColor: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)

        Row {
            id: errorRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingSmall

            Rectangle {
                width: 4; height: errorText.implicitHeight
                radius: 2
                color: Theme.error
            }

            Text {
                id: errorText
                text: root.errorMessage
                font.pixelSize: Theme.fontMedium
                color: Theme.textPrimary
                wrapMode: Text.Wrap
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
            }

            MouseArea {
                width: 24; height: 24
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    root.errorMessage = ""
                    root.dismissed()
                }

                Text {
                    text: "\u2715"
                    font.pixelSize: Theme.fontMedium
                    color: Theme.textSecondary
                    anchors.centerIn: parent
                }
            }
        }
    }

    Timer {
        interval: root.autoHideMs
        running: root.visible && root.autoHideMs > 0
        onTriggered: {
            root.errorMessage = ""
            root.dismissed()
        }
    }
}
