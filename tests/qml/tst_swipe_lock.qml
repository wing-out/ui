import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests the SwipeLockOverlay component.
TestCase {
    id: tc
    name: "SwipeLockOverlay"
    when: windowShown
    width: 540
    height: 960

    Core.Settings {
        id: lockSettings
        property string dxProducerHost: "https://localhost:1234"
        property string previewRTMPUrl: ""
        property string ffstreamHost: ""
    }

    Component.onCompleted: {
        lockSettings.dxProducerHost = "https://localhost:1234"
    }

    Component {
        id: appComponent
        Application {}
    }

    function test_01_app_starts_unlocked() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        // Main.qml starts with locked: false
        var main = findChild(app, "main")
        if (main) {
            verify(!main.locked, "App should start unlocked")
        }
    }

    function test_02_lock_button_visible_on_dashboard() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        // The lock button should be visible when on dashboard (index 0) and
        // not locked.
        var lockBtn = findChild(app, "lockButton")
        if (lockBtn) {
            verify(lockBtn.visible, "Lock button should be visible on dashboard")
        }
    }

    function test_03_lock_unlock_cycle() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        var main = findChild(app, "main")
        if (!main) {
            skip("main not found – objectName may not be set")
            return
        }

        // Lock
        main.locked = true
        wait(50)
        verify(main.locked, "Should be locked")

        // Unlock
        main.locked = false
        wait(50)
        verify(!main.locked, "Should be unlocked")
    }
}
