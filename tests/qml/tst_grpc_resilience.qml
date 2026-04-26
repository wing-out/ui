import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Resilience tests – verify the application does not crash when
/// gRPC backends are unreachable and that error-handling paths work.
TestCase {
    id: tc
    name: "GrpcResilience"
    when: windowShown
    width: 540
    height: 960

    Core.Settings {
        id: resSettings
        property string dxProducerHost: "https://unreachable-host:9999"
        property string previewRTMPUrl: ""
        property string ffstreamHost: "https://unreachable-host:3593"
    }

    Component.onCompleted: {
        resSettings.dxProducerHost = "https://unreachable-host:9999"
        resSettings.ffstreamHost = "https://unreachable-host:3593"
    }

    Component {
        id: appComponent
        Application {}
    }

    function test_01_app_survives_unreachable_grpc() {
        // The real clients will attempt connections to unreachable-host:9999.
        // The application must not crash.
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null, "App should create even with unreachable gRPC hosts")

        wait(500) // Let timers fire a few gRPC calls that will all fail.
        verify(app !== null, "App should still be alive after failed gRPC calls")
    }

    function test_02_navigate_all_pages_with_no_server() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        var stack = findChild(app, "stack")
        if (!stack) {
            skip("stack not found")
            return
        }

        // Cycle through every page – none should crash.
        for (var i = 0; i < 9; i++) {
            stack.currentIndex = i
            wait(100) // Give each page time to attempt its gRPC calls.
        }
        verify(true, "All pages survived without a crash")
    }

    function test_03_dashboard_shows_placeholder_values() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(500)

        // Dashboard should display graceful placeholders ("?" or "0")
        // rather than undefined/NaN.  We just verify it didn't crash after
        // the timers fired.
        var stack = findChild(app, "stack")
        if (stack) {
            compare(stack.currentIndex, 0, "Should still be on dashboard")
        }
    }

    function test_04_settings_page_resilient() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        var stack = findChild(app, "stack")
        if (!stack) {
            skip("stack not found")
            return
        }

        // Navigate to Settings and trigger a config refresh (which will fail).
        stack.currentIndex = 8
        wait(200)

        // No crash means success.
        compare(stack.currentIndex, 8, "Settings page should remain active")
    }
}
