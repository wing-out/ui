/* This file implements the root application window for WingOut. */
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtCore
import WingOut 1.0

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out")

    Component.onCompleted: {
        Qt.application.organizationName = "WingOut"
        Qt.application.organizationDomain = "wingout.app"
        Qt.application.applicationName = "WingOut"
    }

    Settings {
        id: appSettings
        property string dxProducerHost: ""
    }

    InitialSetup {
        id: setupWindow
        // Re-inject Settings directly in InitialSetup.qml or use property
        appSettings: appSettings
        visible: !appSettings.dxProducerHost
    }

    Component {
        id: mainComponent
        Main {
            dxProducerHost: appSettings.dxProducerHost
        }
    }

    Loader {
        id: mainLoader
        anchors.fill: parent
        active: !!appSettings.dxProducerHost
        sourceComponent: mainComponent
    }
}
