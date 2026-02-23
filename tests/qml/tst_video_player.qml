import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Tests the VideoPlayerRTMP component in isolation (no actual RTMP stream).
TestCase {
    id: tc
    name: "VideoPlayerRTMP"
    when: windowShown
    width: 540
    height: 300

    Component {
        id: playerComp
        VideoPlayerRTMP {
            width: 320
            height: 240
        }
    }

    function test_01_creates() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null, "VideoPlayerRTMP should instantiate")
    }

    function test_02_default_muted() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null)
        verify(p.audioMuted === true, "Audio should be muted by default")
    }

    function test_03_stream_name_property() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null)
        p.streamName = "test-stream"
        compare(p.streamName, "test-stream", "streamName should be settable")
    }
}
