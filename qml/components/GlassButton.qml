import QtQuick
import QtQuick.Controls.Material
import WingOut

AbstractButton {
    id: root

    property color accentColor: Theme.accentPrimary
    property bool filled: false
    property string iconText: ""

    // Auto-select black or white text for readability on the filled accent background
    readonly property color filledTextColor:
        (accentColor.r * 0.299 + accentColor.g * 0.587 + accentColor.b * 0.114) > 0.5
        ? "#000000" : "#FFFFFF"

    Accessible.name: root.objectName || root.text
    Accessible.description: root.text
    Accessible.role: Accessible.Button

    implicitWidth: contentRow.implicitWidth + Theme.spacingLarge * 2
    implicitHeight: Theme.buttonHeight

    background: Rectangle {
        radius: Theme.glassRadius / 2
        color: {
            if (root.filled) {
                return root.pressed ? Qt.darker(root.accentColor, 1.2) :
                       root.hovered ? Qt.lighter(root.accentColor, 1.1) :
                       root.accentColor
            }
            return root.pressed ? Theme.surfaceActive :
                   root.hovered ? Theme.surfaceHover :
                   Theme.surfaceColor
        }
        border.width: root.filled ? 0 : Theme.glassBorder
        border.color: Theme.glassBorderColor
        opacity: root.enabled ? 1.0 : 0.5

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }

    contentItem: Item {
        Row {
            id: contentRow
            spacing: Theme.spacingSmall
            anchors.centerIn: parent

            Text {
                visible: root.iconText !== ""
                text: root.iconText
                font.pixelSize: Theme.fontLarge
                color: root.filled ? root.filledTextColor : Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.text
                font.pixelSize: Theme.fontMedium
                font.weight: Font.Medium
                color: root.filled ? root.filledTextColor : Theme.textPrimary
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

}
