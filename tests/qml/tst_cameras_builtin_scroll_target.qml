import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Regression test for #15 (second-tap repro).
///
/// When the user taps an already-focused outputUrlField a second time
/// (to reposition the cursor before editing), Android can switch the
/// window from adjustResize back to overlay mode WITHOUT firing any
/// Qt.inputMethod.visibleChanged or keyboardRectangleChanged signal.
/// The Flickable's height bounces from the post-keyboard shrunken
/// value (e.g. 424 logical on Pixel 8a) back to the pre-keyboard
/// full value (e.g. 703), but the keyboard is still drawn over the
/// bottom of the viewport. If scrollOutputUrlIntoView trusts
/// fl.height alone, it computes a target that places the field below
/// the keyboard top — the field disappears.
///
/// The fix tracks the smallest fl.height observed while the IME is
/// visible (settingsScroll.shrunkenViewportFloor) and clamps the
/// effective viewport to that floor when computing the scroll target,
/// regardless of the current fl.height value.
///
/// This test exercises the pure math helper (_computeScrollTarget)
/// with the EXACT instrumented values captured from the bug-repro
/// session on Pixel 8a (commit 6d6b31b APK md5 252ec0f8…). Each
/// case asserts a specific phase of the gesture timeline:
///
///   case A — pre-keyboard (no IME): fl.height=703 effective is fl.height
///   case B — post-keyboard (adjustResize'd): fl.height=424 floor=424
///   case C — second-tap regression (window flip): fl.height=703 floor=424
///   case D — IME hidden, stale floor: fl.height=703 floor=0
///   case E — pad/clamp boundary: fieldBottom near 0 → target clamps to 0
///   case F — content shorter than viewport: maxScroll clamps to 0
///
/// Falsifier intent (RED state): set the function body to
///   var effectiveH = flHeight   // ignore floor
///   ...
/// Cases B, C, E remain plausible-looking but case C now produces 169
/// (the buggy value) instead of 448 (the fixed value), and the test
/// fails. Falsifier-pair complete.
TestCase {
    id: tc
    name: "CamerasBuiltinScrollTarget"
    when: windowShown

    Component {
        id: rootStub
        QtObject {
            property QtObject grpcCallOptions: QtObject {
                property int deadlineTimeout: 10000
            }
            property QtObject streamingSettings: QtObject {
                property bool active: true
                property int width: 1920
                property int height: 1920
                property int fps: 30
                property int bitrateKbps: 4000
                property int maxBitrateKbps: 8000
                property int audioSampleRate: 48000
                property int audioBitrateKbps: 64
                property int audioChannels: 1
                readonly property string missionVideoCodec: "av1_mediacodec"
                property string videoCodec: "av1_mediacodec"
                property string audioCodec: "aac"
                property string preferredCamera: "Front"
                property int preferredMicrophoneId: 0
                property int activeCameraNum: -1
                property int activeMicrophoneNum: -1
                property int userIntentEpoch: 0
                property string outputUrl: "rtmp://example/url"
                function bumpUserIntentEpoch() {}
                function activate() {}
                function deactivate() {}
            }
            property QtObject ffstreamClient: QtObject {
                function processGRPCError(_) {}
                function getInputsInfo(_, _, _) {}
                function removeInput(_, _, _, _, _) {}
            }
            property QtObject ffstreamCameraClient: QtObject {
                function processGRPCError(_) {}
                function getInputsInfo(_, _, _) {}
                function removeInput(_, _, _, _, _) {}
                function addInput(_, _, _, _, _, _) {}
                function setOutputUrl(_, _, _, _) {}
                function switchOutput(_, _, _, _, _, _, _, _, _, _, _) {}
            }
            property QtObject microphoneController: QtObject {
                property var devices: []
            }
        }
    }

    Component {
        id: camerasBuiltinComponent
        CamerasBuiltin {}
    }

    function _scroll(cb) {
        // CamerasBuiltin exposes settingsScroll via `property alias`
        // for testing (#15 fix). The alias lives at the top of the
        // file alongside outputUrlField and deactivateErrorDialog.
        return cb.settingsScroll || null
    }

    // case A — pre-keyboard. IME hidden, no floor recorded.
    // Effective viewport equals fl.height; target is the standard
    // "scroll the field bottom + pad just above the viewport bottom".
    function test_A_pre_keyboard() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        verify(scroll !== null,
               "settingsScroll must be reachable from the test (children walk)")
        verify(typeof scroll._computeScrollTarget === "function",
               "_computeScrollTarget must be exposed for testing")
        // flH=703 (pre-keyboard), no IME, no floor → effectiveH=703.
        // fb=852, pad=20, contentHeight=873.
        // maxScroll = max(0, 873 - 703) = 170.
        // target = max(0, 852 + 20 - 703) = 169. clamp(169, 170) = 169.
        var t = scroll._computeScrollTarget(703, 873, 852, 20, false, 0)
        compare(t, 169, "pre-keyboard target must be 169 "
                + "(fb+pad-flH = 852+20-703); got " + t)
    }

    // case B — post-keyboard, adjustResize working.
    // fl.height already shrunk; floor matches; effectiveH=floor=fl.height.
    function test_B_post_keyboard_adjustresize() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        // flH=424 (shrunk), IME visible, floor=424 (just captured).
        // fb=852, pad=20, contentHeight=873.
        // maxScroll = max(0, 873 - 424) = 449.
        // target = max(0, 852 + 20 - 424) = 448. clamp(448, 449) = 448.
        var t = scroll._computeScrollTarget(424, 873, 852, 20, true, 424)
        compare(t, 448, "post-keyboard target must be 448 "
                + "(fb+pad-flH = 852+20-424); got " + t)
    }

    // case C — THE BUG — second-tap regression.
    // fl.height bounced back to 703 BUT floor=424 still pinned from
    // first IME-show. With IME still visible, effectiveH must = floor
    // (424), NOT fl.height (703). target must remain 448, NOT 169.
    //
    // Falsifier — change `_computeScrollTarget` body to ignore the
    // floor (effectiveH = flHeight unconditionally) → this test
    // returns 169 and FAILS, demonstrating the test catches the bug.
    function test_C_second_tap_regression() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        var t = scroll._computeScrollTarget(703, 873, 852, 20, true, 424)
        // The whole point: even though fl.height pretends to be 703
        // (Android temporarily flipped to overlay mode), the keyboard
        // is still drawn — the floor is the source of truth.
        compare(t, 448, "second-tap regression: target must clamp to "
                + "floor-derived 448 not fl.height-derived 169 "
                + "(this is the load-bearing assertion for #15); got " + t)
        verify(t !== 169, "target=169 means the floor was IGNORED — "
                + "the bug is back; got " + t)
    }

    // case D — IME hidden but a stale floor lingers. Defensive
    // assertion that the floor is ONLY honored while the IME is up.
    // The visibleChanged handler resets the floor to 0 in production,
    // but we double-check here that even a non-zero stale floor is
    // ignored when imVisible=false.
    function test_D_ime_hidden_floor_ignored() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        // imVisible=false, but floor=424 (defensive simulation).
        // effectiveH must = flH = 703, NOT 424.
        var t = scroll._computeScrollTarget(703, 873, 852, 20, false, 424)
        compare(t, 169, "IME hidden + stale floor: target must use "
                + "fl.height not floor (defensive); got " + t)
    }

    // case E — pad/clamp boundary. Field bottom is above the viewport
    // top (negative target before clamp); must clamp to 0.
    function test_E_target_clamps_to_zero() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        // fieldBottom=10 (top of content), pad=20, flH=200.
        // raw target = max(0, 10 + 20 - 200) = 0.
        var t = scroll._computeScrollTarget(200, 873, 10, 20, false, 0)
        compare(t, 0, "negative raw target must clamp to 0; got " + t)
    }

    // case F — contentHeight smaller than viewport: maxScroll=0
    // means scrolling impossible regardless of target.
    function test_F_short_content_no_scroll() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var scroll = _scroll(cb)
        // contentHeight=300 < flHeight=703 → maxScroll=0.
        // raw target = max(0, 852+20-703) = 169 but clamp(169, 0) = 0.
        var t = scroll._computeScrollTarget(703, 300, 852, 20, false, 0)
        compare(t, 0, "content shorter than viewport must clamp "
                + "target to 0; got " + t)
    }
}
