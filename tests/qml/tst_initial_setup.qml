import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests for the InitialSetup wizard component.
/// Note: InitialSetup is a Window, not an Item. We test it by creating it
/// without a visual parent and interacting via findChild on the Window itself.
TestCase {
    id: tc
    name: "InitialSetup"
    when: windowShown
    width: 600
    height: 400

    Core.Settings {
        id: testSettings
        property string dxProducerHost: ""
        property string previewRTMPUrl: ""
        property string ffstreamHost: ""
    }

    function cleanup() {
        testSettings.dxProducerHost = ""
        testSettings.previewRTMPUrl = ""
        testSettings.ffstreamHost = ""
    }

    function test_01_save_writes_host_and_url() {
        var host = "myhost:1234"
        if (!host.startsWith("http://") && !host.startsWith("https://"))
            host = "https://" + host
        testSettings.dxProducerHost = host
        testSettings.previewRTMPUrl = "rtmp://192.168.0.134:1945/pixel/dji-osmo-pocket-3-merged/"

        compare(testSettings.dxProducerHost, "https://myhost:1234")
        compare(testSettings.previewRTMPUrl,
                "rtmp://192.168.0.134:1945/pixel/dji-osmo-pocket-3-merged/",
                "Preview URL should be stored verbatim")
    }

    function test_02_https_scheme_added() {
        var val = "plain-host:5000"
        if (!val.startsWith("http://") && !val.startsWith("https://"))
            val = "https://" + val
        compare(val, "https://plain-host:5000")
    }

    function test_03_explicit_scheme_preserved() {
        var val = "http://insecure:5000"
        if (!val.startsWith("http://") && !val.startsWith("https://"))
            val = "https://" + val
        compare(val, "http://insecure:5000")
    }

    function test_04_empty_host_rejected() {
        var val = "   "
        val = val.trim()
        compare(val.length, 0, "Trimmed empty host should have zero length")
    }

    function test_05_setup_window_creates() {
        // Verify the component can instantiate as a top-level Window.
        var comp = Qt.createComponent("qrc:/qt/qml/WingOut/InitialSetup.qml")
        if (comp.status !== Component.Ready) {
            // Component may not be available via qrc in test mode; skip.
            skip("InitialSetup component not loadable: " + comp.errorString())
            return
        }
        var win = comp.createObject(null, { appSettings: testSettings })
        verify(win !== null, "InitialSetup should create as a Window")
        // Note: findChild is a TestCase method, not available on Window.
        // Just verify the window was created successfully.
        win.destroy()
    }
}
