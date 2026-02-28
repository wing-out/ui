import QtQuick
import QtQuick.Controls.Material
import WingOut

TextField {
    id: root

    property string placeholder: "Search..."

    Accessible.name: root.objectName || root.placeholder
    Accessible.description: root.text
    Accessible.role: Accessible.EditableText

    placeholderText: root.placeholder
    color: Theme.textPrimary
    placeholderTextColor: Theme.textTertiary
    font.pixelSize: Theme.fontMedium
    implicitHeight: Theme.inputHeight

    background: Rectangle {
        radius: Theme.glassRadius / 2
        color: Theme.surfaceColor
        border.width: root.activeFocus ? 2 : Theme.glassBorder
        border.color: root.activeFocus ? Theme.accentPrimary : Theme.glassBorderColor

        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
    }
}
