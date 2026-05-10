import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Regression test: outputUrlField must NOT propagate every
/// keystroke into settingsController.outputUrl. Pre-fix, the field used
/// `onTextChanged: settingsController.outputUrl = text.trim()` which
/// (with m_active=true) wrote streaming_settings.json on every char,
/// persisting mid-edit IME-injected garbage like
/// `${v:0:height}` → `${v:0:sheight}` to disk. The fix is twofold:
///
///   1. inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText
///      | Qt.ImhNoAutoUppercase | Qt.ImhSensitiveData | Qt.ImhPreferLowercase
///      — makes the IME treat the field as a URL and disables
///      predictive / swipe-to-type, the source of the silent inserts.
///   2. onTextChanged → onEditingFinished — commit at focus-loss / Enter
///      ONLY, not per character. Apply / (Re-)Activate buttons take
///      focus when tapped, which fires onEditingFinished BEFORE
///      onClicked → activate() → writeToFile, so the visible commit
///      semantics are preserved while the per-keystroke writes are
///      eliminated.
///
/// Falsifier intent (RED state): change the field handler back to
/// `onTextChanged: settingsController.outputUrl = text.trim()` (or
/// duplicate the assignment under both onTextChanged AND
/// onEditingFinished) and re-run — test_01 fails because
/// setOutputUrlCalls increments mid-typing instead of remaining 0,
/// test_02 fails because the commit count exceeds 1, and test_04
/// fails because the inputMethodHints assertion regresses.
TestCase {
    id: tc
    name: "CamerasBuiltinOutputUrlCommit"
    when: windowShown
    width: 540
    height: 960

    // Stub root that mirrors a real StreamingSettingsController's
    // outputUrl property/setter contract closely enough for the
    // CamerasBuiltin bindings to evaluate. Crucially, setOutputUrl
    // is observable: each call increments a counter and records the
    // committed value, so the test can distinguish:
    //   - per-keystroke writes (pre-fix bug): N typed chars → N+ calls
    //   - commit-on-blur (post-fix): N typed chars → 0 calls,
    //                                then 1 call when focus is lost
    Component {
        id: rootStub
        QtObject {
            property QtObject grpcCallOptions: QtObject {
                property int deadlineTimeout: 10000
            }
            property QtObject streamingSettings: QtObject {
                // setOutputUrl-call observation surface.
                property int setOutputUrlCalls: 0
                property string lastCommittedOutputUrl: ""

                // The other props that CamerasBuiltin's bindings
                // evaluate at component-load time. Values are
                // arbitrary; the bindings just need to resolve.
                property bool active: true   // simulates Active state — relevant
                                             // because the pre-fix per-keystroke
                                             // setOutputUrl writes were gated on
                                             // m_active.
                property int width: 1920
                property int height: 1920
                property int fps: 30
                property int bitrateKbps: 4000
                property int maxBitrateKbps: 8000
                property int audioSampleRate: 48000
                property int audioBitrateKbps: 64
                property int audioChannels: 1
                readonly property string requiredVideoCodec: "av1_mediacodec"
                property string videoCodec: "av1_mediacodec"
                property string audioCodec: "aac"
                property string preferredCamera: "Front"
                property int preferredMicrophoneId: 0
                property int activeCameraNum: -1
                property int activeMicrophoneNum: -1
                property int userIntentEpoch: 0
                // The outputUrl that CamerasBuiltin's TextField binds to.
                // Its setter is the contract under test: pre-fix code
                // hit it on every keystroke; post-fix only on
                // editing-finished.
                property string outputUrl: "rtmp://avd:1946/live/builtincamera-${v:0:codec}${a:0:codec}-${v:0:height}${a:0:rate}/"

                function cameraIndexForPreferredCamera(camera) {
                    return camera === "Back" ? 0 : 1
                }
                function bumpUserIntentEpoch() {}
                function activate() { /* no-op for this test */ }
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

            // Helper: hook the streamingSettings.outputUrl write side
            // (the CamerasBuiltin TextField fires
            // `settingsController.outputUrl = text.trim()` on commit).
            // QtObject doesn't directly let us define a custom setter,
            // so we re-route via a property-change listener that
            // observes the assignment and bumps the call counter.
            // initial value seeding so the listener discounts the
            // first programmatic seed write.
            Component.onCompleted: {
                streamingSettings.onOutputUrlChanged.connect(function() {
                    streamingSettings.setOutputUrlCalls += 1
                    streamingSettings.lastCommittedOutputUrl = streamingSettings.outputUrl
                })
            }
        }
    }

    Component {
        id: camerasBuiltinComponent
        CamerasBuiltin {}
    }

    // Sentinel item used as the focus-loss target. Setting its
    // forceActiveFocus pulls focus off the TextField, firing
    // outputUrlField.onEditingFinished — the commit boundary.
    Item {
        id: focusSink
        objectName: "focusSink"
        focus: false
        activeFocusOnTab: true
        // Must be visible-tree to actually accept focus.
        width: 10; height: 10
    }

    // test_01: Mid-edit text mutation must NOT propagate to
    // settingsController.outputUrl. Direct contract for the fix.
    function test_01_midedit_does_not_commit() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        verify(stubRoot !== null)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null)

        var field = cb.outputUrlField || null
        verify(field !== null,
               "outputUrlField alias must be addressable from the test "
               + "(see CamerasBuiltin.qml `property alias outputUrlField`)")

        var initialUrl = stubRoot.streamingSettings.outputUrl
        var initialCalls = stubRoot.streamingSettings.setOutputUrlCalls

        // Force focus onto the field — required for editing to be
        // semantically "in progress" from Qt's perspective.
        field.forceActiveFocus()
        verify(field.activeFocus, "field must hold active focus")

        // Simulate the IME inserting a character mid-edit. Setting
        // text imperatively breaks the binding (same as user typing
        // would — the underlying QQuickTextInput updates internally),
        // and onTextChanged WOULD fire here on the pre-fix code path.
        field.text = "X" + field.text

        // Pump the event loop briefly so any (incorrect) deferred
        // commit handlers have a chance to fire.
        wait(50)

        // ASSERT: outputUrl unchanged on the controller, AND no
        // additional setOutputUrl-write occurred. Either failure
        // indicates the pre-fix behavior has resurfaced.
        compare(stubRoot.streamingSettings.outputUrl, initialUrl,
                "settingsController.outputUrl must NOT change while the "
                + "field has focus and text is being edited")
        compare(stubRoot.streamingSettings.setOutputUrlCalls, initialCalls,
                "setOutputUrl must not be invoked per-keystroke "
                + "(pre-fix outputUrl-on-keystroke bug)")
    }

    // test_02: On focus loss (the natural commit boundary used by the
    // Apply/Activate buttons), exactly ONE commit must occur and it
    // must carry the final field text.
    function test_02_focus_loss_commits_exactly_once() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var field = cb.outputUrlField
        verify(field !== null)

        field.forceActiveFocus()
        verify(field.activeFocus)

        var initialCalls = stubRoot.streamingSettings.setOutputUrlCalls

        // Multi-character mid-edit churn. Pre-fix, this would emit
        // five setOutputUrl writes; post-fix, zero (focus still held).
        field.text = "rtmp://example/ZZZZZ"
        wait(20)
        field.text = "rtmp://example/ZZZ"   // user backspaced
        wait(20)
        field.text = "rtmp://example/Zfinal"

        compare(stubRoot.streamingSettings.setOutputUrlCalls, initialCalls,
                "Mid-edit churn must not commit. Pre-fix code path emitted "
                + "one write per text change, this test catches that "
                + "regression.")

        // Move focus off the field — the commit boundary.
        focusSink.forceActiveFocus()
        // onEditingFinished fires when activeFocus transitions to
        // false; give Qt a tick to deliver it.
        wait(50)
        verify(!field.activeFocus, "focus must have moved off the field")

        // EXACTLY ONE commit since this test started.
        compare(stubRoot.streamingSettings.setOutputUrlCalls,
                initialCalls + 1,
                "exactly one setOutputUrl call must have happened on "
                + "focus loss; got "
                + stubRoot.streamingSettings.setOutputUrlCalls
                + " (started at " + initialCalls + ")")
        compare(stubRoot.streamingSettings.lastCommittedOutputUrl,
                "rtmp://example/Zfinal",
                "the committed value must be the field's final text")
    }

    // test_03: Re-focusing and editing again must NOT re-commit until
    // the next focus loss. Demonstrates the contract holds across
    // multiple edit cycles, not just the first.
    function test_03_subsequent_edits_only_commit_on_subsequent_blur() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var field = cb.outputUrlField

        // First edit cycle.
        field.forceActiveFocus()
        field.text = "rtmp://first/url"
        focusSink.forceActiveFocus()
        wait(50)
        var afterFirstCommit = stubRoot.streamingSettings.setOutputUrlCalls

        // Second edit cycle: focus back, edit, but do NOT blur.
        field.forceActiveFocus()
        field.text = "rtmp://second/url"
        wait(50)
        compare(stubRoot.streamingSettings.setOutputUrlCalls,
                afterFirstCommit,
                "second-cycle mid-edit must not commit")

        // Third edit-mutation in same cycle — also must not commit.
        field.text = "rtmp://second/url-EDITED"
        wait(20)
        compare(stubRoot.streamingSettings.setOutputUrlCalls,
                afterFirstCommit,
                "additional mid-edit churn in the same focus session "
                + "must still not commit")

        // NOW blur: exactly one more commit, with the final text.
        focusSink.forceActiveFocus()
        wait(50)
        compare(stubRoot.streamingSettings.setOutputUrlCalls,
                afterFirstCommit + 1,
                "blur after second edit cycle commits exactly once more")
        compare(stubRoot.streamingSettings.lastCommittedOutputUrl,
                "rtmp://second/url-EDITED",
                "last commit reflects the final mid-edit text")
    }

    // test_04: inputMethodHints carry every flag we depend on for the
    // IME behavior contract. The Android-Qt-6 swipe-to-type path was
    // confirmed in production to silently insert characters into the
    // URL during cursor-handle drag (e.g. `${v:0:height}` →
    // `${v:0:sheight}`); ImhNoPredictiveText is the specific flag
    // that disables it. ImhUrlCharactersOnly + ImhNoAutoUppercase +
    // ImhSensitiveData + ImhPreferLowercase are the supporting
    // defenses (URL keyboard layout, no auto-Cap on first char, no
    // learned-text suggestions, lowercase by default for
    // case-sensitive RTMP servers). All five flags must be present.
    function test_04_input_method_hints_block_swipe_to_type() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var field = cb.outputUrlField
        verify(field !== null)

        var hints = field.inputMethodHints
        verify((hints & Qt.ImhNoPredictiveText) !== 0,
               "ImhNoPredictiveText is the load-bearing flag for the "
               + "keystroke-write fix — it disables Gboard's "
               + "swipe-to-type which silently inserts characters into "
               + "the field during cursor-handle drag. "
               + "inputMethodHints=" + hints)
        verify((hints & Qt.ImhUrlCharactersOnly) !== 0,
               "ImhUrlCharactersOnly missing — IME should surface the "
               + "URL keyboard layout. inputMethodHints=" + hints)
        verify((hints & Qt.ImhNoAutoUppercase) !== 0,
               "ImhNoAutoUppercase missing — IME may auto-capitalize "
               + "the first char of the URL. inputMethodHints=" + hints)
        verify((hints & Qt.ImhSensitiveData) !== 0,
               "ImhSensitiveData missing — IME may surface learned-text "
               + "suggestions for the URL contents. inputMethodHints="
               + hints)
        verify((hints & Qt.ImhPreferLowercase) !== 0,
               "ImhPreferLowercase missing — RTMP host/path is "
               + "case-sensitive in some server implementations and "
               + "the default should be lowercase. inputMethodHints="
               + hints)
    }
}
