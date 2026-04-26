/* This file implements the root application window for WingOut. */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtCore as Core
import WingOut 1.0

ApplicationWindow {
    id: application
    width: 1080
    height: 1920
    visible: true
    readonly property var externalPlatformInstance: platformInstance
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out")

    Component.onCompleted: {
        // Only set org/app name when not already overridden (e.g. by tests).
        if (Qt.application.organizationName === "")
            Qt.application.organizationName = "WingOut"
        if (Qt.application.organizationDomain === "")
            Qt.application.organizationDomain = "wingout.app"
        if (Qt.application.applicationName === "")
            Qt.application.applicationName = "WingOut"
    }

    // Use qualified import to avoid shadowing by local Settings.qml
    // (which is a Page component for the config editor, not QSettings).
    Core.Settings {
        id: appSettings
        property string dxProducerHost: ""
        property string previewRTMPUrl: ""
        property string ffstreamHost: ""
        // Empty string means "auto-pick first enabled player".
        property string chosenPlayerStreamID: ""
    }

    readonly property bool setupRequired: !appSettings.dxProducerHost

    Loader {
        id: setupLoader
        objectName: "setupLoader"
        active: application.setupRequired
        onLoaded: item.appSettings = appSettings
        sourceComponent: Component {
            InitialSetup {
                objectName: "setupWindow"
                visible: true
                onFinished: setupLoader.active = false
            }
        }
    }

    Loader {
        id: mainLoader
        objectName: "mainLoader"
        anchors.fill: parent
        active: !application.setupRequired
        sourceComponent: Component {
            Main {
                platformInstance: application.externalPlatformInstance
                appSettings: appSettings
            }
        }
    }
}
