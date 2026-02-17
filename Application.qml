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

    // Use qualified import to avoid shadowing by local Settings.qml
    // (which is a Page component for the config editor, not QSettings).
    Core.Settings {
        id: appSettings
        property string dxProducerHost: ""
        property string previewRTMPUrl: ""
        property string previewRTMPPort: ""
        property string previewRTMPStreamID: ""
        property string ffstreamHost: ""
    }

    readonly property bool hasPreviewConfig: appSettings.previewRTMPUrl !== "" || appSettings.previewRTMPPort !== "" || appSettings.previewRTMPStreamID !== ""
    readonly property bool setupRequired: !appSettings.dxProducerHost || !hasPreviewConfig

    Component.onCompleted: {
        Qt.application.organizationName = "WingOut"
        Qt.application.organizationDomain = "wingout.app"
        Qt.application.applicationName = "WingOut"
        console.log("Application.qml: dxProducerHost:", appSettings.dxProducerHost, "previewRTMPUrl:", appSettings.previewRTMPUrl, "previewRTMPPort:", appSettings.previewRTMPPort, "previewRTMPStreamID:", appSettings.previewRTMPStreamID);
        console.log("Application.qml: hasPreviewConfig:", hasPreviewConfig, "setupRequired:", setupRequired);
    }

    Loader {
        id: setupLoader
        active: application.setupRequired
        onLoaded: item.appSettings = appSettings
        sourceComponent: Component {
            InitialSetup {
                visible: true
                onFinished: setupLoader.active = false
            }
        }
    }

    Loader {
        id: mainLoader
        anchors.fill: parent
        active: !application.setupRequired
        sourceComponent: Component {
            Main {
                dxProducerHost: appSettings.dxProducerHost
                platformInstance: platformInstance
                appSettings: appSettings
            }
        }
    }
}
