import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
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
        currentIndex: stack.currentIndex

        TabButton {
            text: "Dashboard"
        }
        TabButton {
            text: "Cameras"
        }
        //TabButton { text: "Settings" }

        onCurrentIndexChanged: stack.currentIndex = currentIndex
    }

    SwipeView {
        id: stack
        anchors.fill: parent
        currentIndex: 0
        Loader {
            source: "Dashboard.qml"
        }
        Loader {
            source: "Cameras.qml"
        }
        //Loader { source: "Settings.qml" }
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
