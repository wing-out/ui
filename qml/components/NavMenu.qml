import QtQuick
import QtQuick.Controls.Material
import WingOut

Rectangle {
    id: root

    property int currentIndex: 0
    property bool isOpen: false

    signal pageSelected(int index)

    Accessible.name: "navMenu"
    Accessible.role: Accessible.List

    width: Theme.navMenuWidth
    color: Theme.backgroundSecondary
    border.width: Theme.glassBorder
    border.color: Theme.glassBorderColor

    ListModel {
        id: menuModel
        ListElement { menuIcon: "\ue871"; label: "Dashboard" }
        ListElement { menuIcon: "\ue88a"; label: "Status" }
        ListElement { menuIcon: "\ue3af"; label: "Cameras" }
        ListElement { menuIcon: "\ue539"; label: "DJI Control" }
        ListElement { menuIcon: "\ue0cb"; label: "Chat" }
        ListElement { menuIcon: "\ue037"; label: "Players" }
        ListElement { menuIcon: "\ue8d4"; label: "Restreams" }
        ListElement { menuIcon: "\ue333"; label: "Monitor" }
        ListElement { menuIcon: "\ue853"; label: "Profiles" }
        ListElement { menuIcon: "\ue868"; label: "Logs" }
        ListElement { menuIcon: "\ue8b8"; label: "Settings" }
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Theme.spacingLarge
        spacing: 0

        // App title
        Item {
            width: parent.width
            height: 60

            Text {
                text: "WingOut"
                font.pixelSize: Theme.fontHuge
                font.weight: Font.Bold
                color: Theme.accentPrimary
                anchors.centerIn: parent
            }
        }

        Rectangle {
            width: parent.width - Theme.spacingLarge * 2
            height: 1
            color: Theme.glassBorderColor
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Item { width: 1; height: Theme.spacingMedium }

        Repeater {
            model: menuModel

            delegate: AbstractButton {
                required property int index
                required property string menuIcon
                required property string label

                Accessible.name: label
                Accessible.role: Accessible.Button
                width: root.width - Theme.spacingSmall * 2
                height: 48
                anchors.horizontalCenter: parent.horizontalCenter

                background: Rectangle {
                    radius: Theme.glassRadius / 2
                    color: {
                        if (index === root.currentIndex) return Theme.surfaceActive
                        if (parent.hovered) return Theme.surfaceHover
                        return "transparent"
                    }
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }

                Rectangle {
                    visible: index === root.currentIndex
                    width: 3
                    height: parent.height - 12
                    radius: 2
                    color: Theme.accentPrimary
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                }

                contentItem: Row {
                    leftPadding: Theme.spacingMedium
                    spacing: Theme.spacingMedium

                    Text {
                        text: menuIcon
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fontLarge
                        color: index === root.currentIndex ? Theme.accentPrimary : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        text: label
                        font.pixelSize: Theme.fontMedium
                        font.weight: index === root.currentIndex ? Font.Medium : Font.Normal
                        color: index === root.currentIndex ? Theme.textPrimary : Theme.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                onClicked: {
                    root.currentIndex = index
                    root.pageSelected(index)
                }
            }
        }
    }
}
