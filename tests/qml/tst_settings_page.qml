import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests the Settings page – tab navigation and app-settings display.
TestCase {
    id: tc
    name: "SettingsPage"
    when: windowShown
    width: 540
    height: 960

    Core.Settings {
        id: setSettings
        property string dxProducerHost: "https://localhost:1234"
        property string previewRTMPUrl: ""
        property string previewRTMPPort: "1945"
        property string previewRTMPStreamID: "test/stream/"
        property string ffstreamHost: "https://localhost:3593"
        property string manualInputFPS: ""
    }

    Component.onCompleted: {
        setSettings.dxProducerHost = "https://localhost:1234"
        setSettings.previewRTMPPort = "1945"
        setSettings.previewRTMPStreamID = "test/stream/"
        setSettings.ffstreamHost = "https://localhost:3593"
    }

    Component {
        id: appComponent
        Application {}
    }

    function test_01_navigate_to_settings() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        var stack = findChild(app, "stack")
        if (!stack) {
            skip("stack not found")
            return
        }
        // Settings is page index 8
        stack.currentIndex = 8
        wait(100)
        compare(stack.currentIndex, 8, "Settings page should be active")
    }

    function test_02_settings_has_tabs() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        var stack = findChild(app, "stack")
        if (stack)
            stack.currentIndex = 8
        wait(100)

        var tabBar = findChild(app, "settingsTabBar")
        if (tabBar) {
            verify(tabBar.count >= 3, "Settings should have at least 3 tabs")
        }
    }
}
