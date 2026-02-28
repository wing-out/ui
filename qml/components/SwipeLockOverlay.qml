import QtQuick
import WingOut

Rectangle {
    id: root

    property bool locked: false

    Accessible.name: "lockOverlay"
    Accessible.description: root.locked ? "locked" : "unlocked"
    Accessible.role: Accessible.Pane

    visible: locked
    color: "transparent"

    // Consume all touch/mouse events so nothing underneath can react
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        hoverEnabled: true
    }
}
