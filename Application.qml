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
        // Optional raw-camera preview RTMP URL: when the dashboard's
        // raw-source toggle is engaged, the video player binds to this URL
        // instead of the configured preview. Empty means "no raw preview
        // configured"; the toggle becomes a no-op in that case. This is a
        // deployment-specific stream URL (e.g. the route a local mediamtx
        // exposes for the upstream camera proxy); leave blank for general
        // deployments.
        property string rawCameraPreviewUrl: ""
        // Optional low-bitrate preview RTMP URL: when the player switches
        // to a low-bitrate variant (e.g. on poor link quality), it binds
        // to this URL. Empty means "no low-bitrate variant configured";
        // the player keeps using the regular preview URL. This is a
        // deployment-specific stream URL; leave blank for general
        // deployments.
        property string lowBitratePreviewUrl: ""
        // Optional DJI camera preview RTMP route stem: when the user
        // configures DJI hotspot streaming, the DJI control page
        // composes a default RTMP publish URL as
        // `rtmp://<hotspot-ip>:1935/<djiPreviewRouteStem>`. The route
        // stem is a deployment choice (the route name your local
        // mediamtx exposes for DJI camera ingest). Empty means "no
        // default published; user types one in"; the TextField stays
        // empty in that case. Leave blank for general deployments.
        property string djiPreviewRouteStem: ""
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
