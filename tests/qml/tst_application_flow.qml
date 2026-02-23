import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// End-to-end flow: app launch → setup wizard → main dashboard.
TestCase {
    id: tc
    name: "ApplicationFlow"
    when: windowShown
    width: 540
    height: 960

    // ---- helpers ----
    Component {
        id: appComponent
        Application {}
    }

    // ---- tests ----

    function test_01_app_creates_without_crash() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null, "Application should instantiate")
        verify(app.visible, "Application window should be visible")
    }

    function test_02_setup_required_when_settings_empty() {
        // With a fresh QSettings (cleared in C++ setup), all host fields are
        // empty → setupRequired should be true.
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        verify(app.setupRequired, "Setup should be required with empty settings")
    }

    function test_03_setup_wizard_visible_initially() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)

        // InitialSetup is a separate Window – findChild cannot reach it
        // because Windows don't live in the Item tree.  Instead, verify
        // the setupRequired gate (which drives the wizard's visibility).
        verify(app.setupRequired, "Setup should be required")

        // The mainLoader should be inactive while setup is required.
        var loader = findChild(app, "mainLoader")
        if (loader) {
            verify(!loader.active, "Main loader should be inactive during setup")
        }
    }

    function test_04_main_hidden_until_setup_done() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)

        // The Loader for Main should be inactive while setup is required.
        var loader = findChild(app, "mainLoader")
        if (loader) {
            verify(!loader.active, "Main loader should be inactive during setup")
        }
    }

    function test_05_settings_persistence() {
        // Write settings, recreate app, verify setup is no longer required.
        var settings = Qt.createQmlObject(
            'import QtCore\n' +
            'Settings {\n' +
            '    property string dxProducerHost: ""\n' +
            '    property string previewRTMPUrl: ""\n' +
            '    property string previewRTMPPort: ""\n' +
            '    property string previewRTMPStreamID: ""\n' +
            '}', tc)
        settings.dxProducerHost = "https://test-host:1234"
        settings.previewRTMPPort = "1945"
        settings.previewRTMPStreamID = "test/stream/"
        settings.destroy()

        // Wait for QSettings to flush.
        wait(100)

        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        verify(!app.setupRequired,
               "Setup should NOT be required after settings are saved")
    }
}
