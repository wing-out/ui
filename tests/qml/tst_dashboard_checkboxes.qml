import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtTest
import QtCore as Core
import WingOut

/// E2E verification of the Dashboard CheckBox UI change. The full Application
/// crashes during load on this build (pre-existing Qt6 multimedia FFmpeg
/// SIGSEGV when two MediaPlayers initialise simultaneously — also reproduces
/// in tst_application_flow), so we render the Dashboard.qml component with a
/// mocked `root` that satisfies its required properties. We assert the three
/// Music / Subs / Sound controls expose the QtQuick.Controls 2 CheckBox
/// `nextCheckState` callback (Button does not), and that toggling Sound flips
/// `checked`. A best-effort screenshot is also captured to
/// /tmp/wingout-checkboxes.png for visual review, but its success is not part
/// of the pass criteria.
TestCase {
    id: tc
    name: "DashboardCheckboxes"
    when: windowShown
    width: 1080
    height: 1920
    visible: true

    // Mock objects exposing only the methods/properties Dashboard touches.
    QtObject {
        id: stubAppSettings
        property bool soundEnabled: false
        property string previewRTMPUrl: ""
        property string dxProducerHost: "https://localhost:1234"
        property string ffstreamHost: ""
    }

    QtObject {
        id: stubGrpcCallOptions
    }

    QtObject {
        id: stubClient
        function ping() {}
        function getLatencies() {}
        function getInputQuality() {}
        function getFPSFraction() {}
        function getOutputQuality() {}
        function getBitRates() {}
        function getPlayerLag() {}
        function listStreamPlayers() {}
        function subscribeToChatMessages() {}
        function setVariable(name, value, ok, err, opts) { /* no-op */ }
        function getVariable(name, ok, err, opts) { /* no-op */ }
        function getBackendInfo() {}
        function banUser() {}
        function listProfiles() {}
        function listStreamSources() {}
        function listStreamServers() {}
        function reconnect() {}
        property var processGRPCError: undefined
    }

    ListModel {
        id: stubChatModel
    }

    QtObject {
        id: stubRoot
        property var appSettings: stubAppSettings
        property var dxProducerClient: stubClient
        property var ffstreamClient: stubClient
        property var grpcCallOptions: stubGrpcCallOptions
        property var streamingGrpcCallOptions: stubGrpcCallOptions
        property var globalChatMessagesModel: stubChatModel
        property string dxProducerHost: "https://localhost:1234"
        function processStreamDGRPCError() {}
        function processFFStreamGRPCError() {}
        function checkStreamDClient() { return false } // disables RPC paths
        function fireMultiPlatformRPC() {}
        property var platformCapabilities: ({})
    }

    Component {
        id: dashboardComp
        Dashboard {
            anchors.fill: parent
            root: stubRoot
            platformCapabilities: ({})
        }
    }

    function test_capture_dashboard_checkboxes() {
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null, "Dashboard must instantiate")

        // Allow Dashboard to render. checkStreamDClient() returns false so
        // RPC paths short-circuit and no MediaPlayer is wired to a live URL.
        wait(800)

        // Discriminator: object exposes the QtQuick.Controls 2 CheckBox 'checkState' property (Button does not).
        function findControlByText(root, label) {
            if (!root) return null
            if (typeof root.text !== "undefined" && root.text === label
                && typeof root.checkState !== "undefined") {
                return root
            }
            for (var i = 0; i < (root.children ? root.children.length : 0); i++) {
                var hit = findControlByText(root.children[i], label)
                if (hit) return hit
            }
            return null
        }
        var musicCb = findControlByText(dashboard, "Music")
        var subsCb  = findControlByText(dashboard, "Subs")
        var soundCb = findControlByText(dashboard, "Sound")
        verify(musicCb !== null, "Music must be a CheckBox")
        verify(subsCb  !== null, "Subs must be a CheckBox")
        verify(soundCb !== null, "Sound must be a CheckBox")

        // Sound's nextCheckState toggles via appSettings.soundEnabled — the
        // mock settings object accepts the assignment, so toggling should be
        // observable on `checked`.
        var beforeSound = soundCb.checked
        soundCb.toggle()
        wait(50)
        var afterSound = soundCb.checked
        verify(beforeSound !== afterSound, "Sound CheckBox toggle must flip checked state")

        // Restore Sound to a checked state for the screenshot.
        if (!soundCb.checked) {
            soundCb.toggle()
            wait(50)
        }

        // Best-effort screenshot for visual review. NOT part of pass criteria —
        // failure to write the PNG (e.g. /tmp not writable, headless GPU
        // limitations) must not fail the test; the CheckBox assertions above
        // are the actual contract.
        var captured = false
        var ok = tc.grabToImage(function(result) {
            var saved = result.saveToFile("/tmp/wingout-checkboxes.png")
            console.log("tst_dashboard_checkboxes: grabToImage saveToFile -> " + saved)
            captured = true
        })
        if (ok) {
            tryVerify(function() { return captured }, 5000,
                      "Screenshot scheduled but never completed")
        }
    }
}
