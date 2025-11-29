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

    onClosing: {
        close.accepted = false;
        inputBlocker.visible = true;
    }

    MouseArea {
        id: inputBlocker
        anchors.fill: parent
        z: 9999
        visible: false
        enabled: true // Set to false to unlock
        opacity: 0.0
        property real startX: 0
        property real startY: 0
        onClicked: {}
        onPressed: {
            inputBlocker.startX = mouse.x;
            inputBlocker.startY = mouse.y;
        }
        onReleased: {
            var deltaY = mouse.y - inputBlocker.startY;
            var deltaX = mouse.x - inputBlocker.startX;
            if (deltaY >= -200) {
                return;
            }
            if (deltaX <= 200 && -deltaX <= 200) {
                return;
            }
            inputBlocker.visible = false;
            platform.vibrate(50, false);
        }
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

        TabButton { text: "Dashboard" }
        //TabButton { text: "Cameras" }
        //TabButton { text: "Settings" }

        onCurrentIndexChanged: stack.currentIndex = currentIndex
    }

    SwipeView {
        id: stack
        anchors.fill: parent
        currentIndex: 0
        Loader { source: "Dashboard.qml" }
        //Loader { source: "Cameras.qml" }
        //Loader { source: "Settings.qml" }
    }
}
