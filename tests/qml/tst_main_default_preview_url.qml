import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// T-1.1 — `Main.defaultPreviewRtmpUrl()` returns the empty string.
///
/// Pins the post-cleanup contract introduced by commits c2d4e64 + 9ddc16a:
/// `defaultPreviewRtmpUrl()` MUST return "" so the dashboard preview stays
/// blank when no `previewRTMPUrl` has been configured by the user. A
/// non-empty return would re-introduce the deployment-overfit default that
/// Task #6 was created to remove.
///
/// Per spec /tmp/claude-plans/task6-phase4-specs.md v3.2.2 Section 3 T-1.1.
TestCase {
    id: tc
    name: "MainDefaultPreviewUrl"
    when: windowShown
    width: 540
    height: 960

    Component {
        id: appSettingsStub
        QtObject {
            // Non-trivial dxProducerHost proves the function does not
            // silently re-derive a URL from it.
            property string dxProducerHost: "https://example.com:3594"
            property string previewRTMPUrl: ""
            property string ffstreamHost: ""
        }
    }

    Component {
        id: platformStub
        QtObject {
            function refreshWiFiState() {}
        }
    }

    Component {
        id: mainComponent
        Main {
            platformInstance: platformStub.createObject(tc)
            appSettings: appSettingsStub.createObject(tc)
        }
    }

    function test_T_1_1_default_preview_url_is_empty() {
        var main = createTemporaryObject(mainComponent, tc)
        verify(main !== null, "Main must instantiate")

        // Assertion 1 — Good IS: function returns empty string.
        compare(main.defaultPreviewRtmpUrl(), "",
                "defaultPreviewRtmpUrl() must return \"\"")

        // Assertion 2 — Bad NOT: no RTMP scheme leaks back in.
        verify(main.defaultPreviewRtmpUrl().indexOf("rtmp://") === -1,
               "no rtmp:// scheme must leak from defaultPreviewRtmpUrl()")

        // Assertion 3 — Bad NOT: function does not re-derive from
        // dxProducerHost (proves the cleanup is structural, not a bypass).
        verify(main.defaultPreviewRtmpUrl().indexOf("example.com") === -1,
               "defaultPreviewRtmpUrl() must NOT re-derive from dxProducerHost")

        // Assertion 4 — Bad NOT: deployment-specific stem is gone.
        verify(main.defaultPreviewRtmpUrl().indexOf("dji-osmo-pocket") === -1,
               "deployment-specific stem must NOT appear")

        // Assertion 5 — Bad NOT: test-phone codename stem is gone.
        verify(main.defaultPreviewRtmpUrl().indexOf("pixel/") === -1,
               "test-phone codename stem must NOT appear")
    }
}
