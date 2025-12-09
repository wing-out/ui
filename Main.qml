import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Platform

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out")

    property bool locked: false

    onClosing: {
        close.accepted = false;
        application.locked = true;
    }

    Platform {
        id: platform
        Component.onCompleted: {
            platform.setEnableRunningInBackground(true);
            platform.startMonitoringSignalStrength();
        }
    }

    header: TabBar {
        id: tabBar
        currentIndex: 0

        TabButton {
            text: "Dashboard"
        }
        TabButton {
            text: "Cameras"
        }
        //TabButton { text: "Settings" }
    }

    StackLayout {
        id: stack
        anchors.fill: parent
        currentIndex: tabBar.currentIndex
        Dashboard {
            id: dashboardPage
        }
        Cameras {
            id: camerasPage
        }
    }

    SwipeLockOverlay {
        id: lockOverlay
        locked: application.locked
        onUnlockRequested: application.locked = false
    }

    Button {
        id: lockButton
        visible: !application.locked
        text: "🔒"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 16
        font.pixelSize: 40
        property real defaultOpacity: 0.7
        opacity: hovered ? 1.0 : defaultOpacity
        onClicked: application.locked = true
    }
}
