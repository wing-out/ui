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
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Wing Out")

    Component.onCompleted: {
        Qt.application.organizationName = "WingOut"
        Qt.application.organizationDomain = "wingout.app"
        Qt.application.applicationName = "WingOut"
    }

    // Use qualified import to avoid shadowing by local Settings.qml
    // (which is a Page component for the config editor, not QSettings).
    Core.Settings {
        id: appSettings
        property string dxProducerHost: ""
    }

    Loader {
        id: setupLoader
        active: !appSettings.dxProducerHost
        // Assign appSettings imperatively: inside a Component{} block the
        // unqualified "appSettings" resolves to InitialSetup's own property
        // (self-reference), not to the outer id.
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
        active: !!appSettings.dxProducerHost
        sourceComponent: Component {
            Main {
                dxProducerHost: appSettings.dxProducerHost
            }
        }
    }
}
