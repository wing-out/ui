import QtQuick
import WingOut

Item {
    id: root

    property alias contentItem: contentArea
    property bool hoverEnabled: false
    property bool hovered: false
    property int radius: Theme.glassRadius
    property color borderColor: Theme.glassBorderColor
    property real surfaceOpacity: Theme.glassOpacity

    default property alias content: contentArea.data

    // Size from content + padding
    implicitHeight: contentArea.childrenRect.height + padding * 2
    implicitWidth: contentArea.childrenRect.width + padding * 2

    property real padding: Theme.spacingMedium

    Rectangle {
        id: glassBackground
        anchors.fill: parent
        radius: root.radius
        color: root.hovered ? Theme.surfaceHover : Theme.surfaceColor
        opacity: root.surfaceOpacity / Theme.glassOpacity

        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        border.width: Theme.glassBorder
        border.color: root.borderColor
    }

    Item {
        id: contentArea
        x: root.padding
        y: root.padding
        width: root.width - root.padding * 2
        height: root.height - root.padding * 2
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.hoverEnabled
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: root.hovered = containsMouse
    }
}
