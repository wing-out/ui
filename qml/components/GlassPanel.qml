import QtQuick
import WingOut

Rectangle {
    id: root

    property bool showBorder: true
    default property alias content: contentArea.data

    color: Theme.backgroundSecondary
    border.width: root.showBorder ? Theme.glassBorder : 0
    border.color: Theme.glassBorderColor

    Item {
        id: contentArea
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
    }
}
