import QtQuick
import WingOut

Rectangle {
    id: root

    property string label: ""
    property color statusColor: Theme.textSecondary
    property bool active: false

    Accessible.name: root.objectName || root.label
    Accessible.description: root.label + (root.active ? ", active" : ", inactive")
    Accessible.role: Accessible.Indicator

    implicitWidth: row.implicitWidth + Theme.spacingMedium * 2
    implicitHeight: Theme.statusBadgeHeight

    radius: height / 2
    color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.15)
    border.width: 1
    border.color: Qt.rgba(root.statusColor.r, root.statusColor.g, root.statusColor.b, 0.3)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingSmall

        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: root.statusColor
            anchors.verticalCenter: parent.verticalCenter

            SequentialAnimation on opacity {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation { to: 0.4; duration: 800 }
                NumberAnimation { to: 1.0; duration: 800 }
            }
        }

        Text {
            text: root.label
            font.pixelSize: Theme.fontSmall
            font.weight: Font.Medium
            color: root.statusColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
