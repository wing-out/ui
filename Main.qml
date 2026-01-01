import QtQuick
import QtQuick.Window
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
    readonly property bool isLandscape: width > height

    property var safeAreaInsets: platform.getSafeAreaInsets()
    onWidthChanged: safeAreaInsets = platform.getSafeAreaInsets()
    onHeightChanged: safeAreaInsets = platform.getSafeAreaInsets()

    readonly property real safeAreaTop: ((safeAreaInsets && safeAreaInsets.top) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaBottom: ((safeAreaInsets && safeAreaInsets.bottom) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaLeft: ((safeAreaInsets && safeAreaInsets.left) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaRight: ((safeAreaInsets && safeAreaInsets.right) || 0) / Screen.devicePixelRatio

    topPadding: safeAreaTop
    leftPadding: safeAreaLeft
    rightPadding: safeAreaRight
    bottomPadding: safeAreaBottom

    Component.onCompleted: {
        console.log("Main: ApplicationWindow completed")
    }

    onClosing: (close) => {
        close.accepted = false;
        application.locked = true;
    }

    Platform {
        id: platform
        Component.onCompleted: {
            platform.setEnableRunningInBackground(true);
            platform.startMonitoringSignalStrength();
            platform.refreshWiFiState();
        }
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state === Qt.ApplicationActive) {
                console.log("Main: Application active, refreshing WiFi state")
                platform.refreshWiFiState()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            currentIndex: 0
            visible: !application.isLandscape

            TabButton {
                text: "Dashboard"
            }
            TabButton {
                text: "Cameras"
            }
            TabButton {
                text: "DJI"
            }
        }

        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            Dashboard {
                id: dashboardPage
            }
            Cameras {
                id: camerasPage
            }
            DJIControl {
                id: djiControlPage
                Component.onCompleted: console.log("Main: DJIControl page completed")
            }
        }
    }

    SwipeLockOverlay {
        id: lockOverlay
        locked: application.locked
        topPadding: application.safeAreaTop
        onUnlockRequested: application.locked = false
    }

    Button {
        id: lockButton
        visible: !application.locked && stack.currentIndex === 0
        text: "🔒"
        anchors.top: stack.top
        anchors.right: stack.right
        anchors.margins: 16
        font.pixelSize: 40
        property real defaultOpacity: 0.7
        opacity: hovered ? 1.0 : defaultOpacity
        onClicked: application.locked = true
    }
}
