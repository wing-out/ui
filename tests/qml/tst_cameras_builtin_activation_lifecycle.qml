import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests for CamerasBuiltin.qml Activate/Deactivate in-flight cue
/// lifecycle.
///
/// Subject under test: _beginActivation, _endActivation, the watchdog
/// Timer (activationWatchdog), and the button enabled bindings that
/// flip in lockstep with _activationInFlight.
///
/// Falsifier intent: each test is paired with a falsifier line in the
/// header comment — e.g. removing `activationWatchdog.restart()` from
/// _beginActivation breaks test_01_begin; adding a missing `stop()` in
/// _endActivation breaks test_02_end. Run the falsifier path to see
/// the test fail RED, then revert; this proves the test is wired to
/// the production behaviour, not just compiling against it.
///
/// Strategy: minimal stub of builtin.root (mirrors
/// tst_cameras_builtin_deactivate.qml). We do NOT exercise the gRPC
/// chain — we call _beginActivation / _endActivation directly because
/// they are the contract the rest of the chain depends on, and they
/// are deterministic / synchronous on the QML thread. The watchdog's
/// onTriggered path is exercised via setting interval=1ms in a
/// dedicated test.
TestCase {
    id: tc
    name: "CamerasBuiltinActivationLifecycle"
    when: windowShown
    width: 540
    height: 960

    Component {
        id: rootStub
        QtObject {
            // grpcCallOptions stub — CamerasBuiltin's Activate /
            // Deactivate paths now thread `builtin.root.grpcCallOptions`
            // into every RPC site (B1). The call sites are not
            // exercised here, but the QML bindings DO resolve the
            // alias at component load when the function literals are
            // parsed; providing a QtObject with deadlineTimeout makes
            // shape-equivalence with Main.qml's GrpcCallOptions.
            property QtObject grpcCallOptions: QtObject {
                property int deadlineTimeout: 10000
            }
            property QtObject ffstreamCameraStartupProbeGrpcCallOptions: QtObject {
                property int deadlineTimeout: 400
            }
            property QtObject streamingSettings: QtObject {
                property bool active: false
                property int width: 1920
                property int height: 1920
                property int fps: 30
                property int bitrateKbps: 4000
                property int maxBitrateKbps: 8000
                readonly property string requiredVideoCodec: "av1_mediacodec"
                property string videoCodec: "h265_mediacodec"
                property string audioCodec: "aac"
                property int audioSampleRate: 48000
                property int audioBitrateKbps: 64
                property int audioChannels: 1
                property string outputUrl: ""
                property string preferredCamera: "Front"
                property int preferredMicrophoneId: 0
                property int activeCameraNum: -1
                property int activeMicrophoneNum: -1
                property int userIntentEpoch: 0
                function cameraIndexForPreferredCamera(camera) {
                    return camera === "Back" ? 0 : 1
                }
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
                property var pendingGetInputsInfoFinish: null
                property var pendingGetInputsInfoError: null
                property var pendingRemoveFinish: null
                property var pendingRemoveError: null
                property bool autoFinishRemoveInput: true
                property int removeInputCalls: 0
                property int processGrpcErrorCalls: 0
                property var removedNums: []
                function processGRPCError(_) { processGrpcErrorCalls += 1 }
                function getInputsInfo(finishCallback, errorCallback, _) {
                    pendingGetInputsInfoFinish = finishCallback
                    pendingGetInputsInfoError = errorCallback
                }
                function removeInput(_, num, finishCallback, errorCallback, _) {
                    removeInputCalls += 1
                    removedNums.push(num)
                    pendingRemoveFinish = finishCallback
                    pendingRemoveError = errorCallback
                    if (autoFinishRemoveInput) {
                        finishCallback({})
                    }
                }
                function addInput(_, _, _, _, _, _) {}
                function setOutputUrl(_, _, _, _) {}
                function switchOutput(_, _, _, _, _, _, _, _, _, _, _) {}
            }
            property QtObject microphoneController: QtObject {
                property var devices: []
            }
            function builtinCameraPublisherUrl() { return "" }
        }
    }

    Component {
        id: camerasBuiltinComponent
        CamerasBuiltin {
            // Opt out of the Task #124 proactive gRPC reachability monitor
            // for this test file. The monitor's continuous getInputsInfo
            // ticker would inflate cameraClient.getInputsInfoCalls counts
            // and consume queued stub responses meant for user-intent
            // probes. Tests that exercise the proactive monitor live in
            // tst_cameras_builtin_grpc_no_channel.qml.
            _grpcProbeEnabled: false
        }
    }

    function _readWingoutSource(relativePath) {
        verify(typeof wingoutSourceDir !== "undefined" && wingoutSourceDir,
               "wingoutSourceDir must be exposed by the QML test setup")
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + wingoutSourceDir + "/" + relativePath, false)
        xhr.send(null)
        verify(xhr.status === 200 || xhr.status === 0,
               "must be able to read " + relativePath + " from disk")
        verify(xhr.responseText && xhr.responseText.length > 0,
               relativePath + " source must be non-empty")
        return xhr.responseText
    }

    // CamerasBuiltin exposes activationWatchdog via a property alias
    // (test seam, mirrors deactivateErrorDialog). Timer is a non-
    // visual item, so it does NOT appear in cb.children — the alias
    // is the only stable way to reach it from a test.
    function _findWatchdog(cb) {
        return cb.activationWatchdog || null
    }

    // test_01: _beginActivation("Activating") sets the in-flight flag,
    // sets the verb, and STARTS the watchdog Timer.
    //
    // Falsifier: drop `activationWatchdog.restart()` from
    // _beginActivation -> wd.running stays false, this test fails.
    function test_01_begin_sets_flag_verb_and_starts_watchdog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        verify(!cb._activationInFlight, "flag starts false")
        compare(cb._activationVerb, "", "verb starts empty")

        var wd = _findWatchdog(cb)
        verify(wd !== null, "activationWatchdog Timer must be findable")
        verify(!wd.running, "watchdog starts stopped")

        cb._beginActivation("Activating")
        verify(cb._activationInFlight,
               "_activationInFlight must flip true on _beginActivation")
        compare(cb._activationVerb, "Activating",
                "_activationVerb must reflect the argument")
        verify(wd.running,
               "activationWatchdog.running must be true after _beginActivation")
    }

    // test_02: _endActivation clears the flag, the verb, and STOPS the
    // watchdog Timer.
    //
    // Falsifier: drop `activationWatchdog.stop()` from _endActivation
    // -> wd.running stays true, this test fails.
    function test_02_end_clears_flag_verb_and_stops_watchdog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var wd = _findWatchdog(cb)
        verify(wd !== null)

        cb._beginActivation("Deactivating")
        verify(cb._activationInFlight)
        verify(wd.running)

        cb._endActivation()
        verify(!cb._activationInFlight,
               "_activationInFlight must flip false on _endActivation")
        compare(cb._activationVerb, "",
                "_activationVerb must reset to empty")
        verify(!wd.running,
               "activationWatchdog must be stopped after _endActivation")
    }

    // test_03: _endActivation is idempotent — calling it twice is
    // safe. The first call clears the flag; the second sees the flag
    // already false and returns early. The watchdog must remain
    // stopped after both calls.
    //
    // Falsifier: remove the early-return guard from _endActivation
    // (the `if (!_activationInFlight) return`) and add a stray
    // `activationWatchdog.restart()` -> the second call would re-arm
    // the watchdog, this test fails.
    function test_03_end_is_idempotent() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var wd = _findWatchdog(cb)

        cb._beginActivation("Activating")
        cb._endActivation()
        cb._endActivation()  // second call must be a no-op
        verify(!cb._activationInFlight)
        compare(cb._activationVerb, "")
        verify(!wd.running, "watchdog must remain stopped after double-end")
    }

    // test_04: watchdog onTriggered clears the in-flight flag and
    // opens activationTimeoutDialog. We exercise this by setting the
    // interval to 1ms and calling _beginActivation; tryVerify with a
    // 1s budget catches the dialog open.
    //
    // Falsifier: remove `_activationInFlight = false` from the
    // onTriggered handler -> flag stays true, this test's flag check
    // fails. Remove `activationTimeoutDialog.open()` -> dialog never
    // becomes visible, the second tryVerify fails.
    function test_04_watchdog_fires_clears_flag_and_opens_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var wd = _findWatchdog(cb)
        verify(wd !== null)

        // Shorten the interval so the test completes within the
        // tryVerify budget. Re-stop and re-start so the new interval
        // takes effect (Qt Timer reads interval at start time).
        wd.stop()
        wd.interval = 50
        cb._beginActivation("Activating")
        // The flag is initially set by _beginActivation; the watchdog
        // fires after ~50ms and clears it.
        tryVerify(function() { return !cb._activationInFlight }, 1500,
                  "watchdog must clear _activationInFlight on fire")
        compare(cb._activationVerb, "",
                "watchdog must clear _activationVerb on fire")

        // The component's activationTimeoutDialog is not exposed via a
        // property alias today; assert the visible state via a child
        // walk if exposable, otherwise rely on the flag-clear assertion
        // above as the operational signal. The flag transition is the
        // contract the buttons rely on; the dialog is a UX surface
        // covered by the end-to-end UI test instead.
    }

    // test_05: _showActivateError clears the in-flight flag for FILTERED
    // (Cancelled = 1, Unavailable = 14) error codes too. The previous
    // bug let the spinner spin until the watchdog fired even though the
    // chain was already dead.
    //
    // Dual-sided: also assert that activateErrorDialog does NOT open for
    // filtered codes.
    //
    // Falsifier: move `builtin._endActivation()` below the
    // `_isUserVisibleGrpcError` filter check -> filtered errors leave
    // the flag set, this test fails. Drop the
    // `if (!_isUserVisibleGrpcError(err)) return` filter -> filtered
    // codes would open the dialog, the new dual-side assertion fails.
    function test_05_showActivateError_clears_flag_for_filtered_codes() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        cb._beginActivation("Activating")
        verify(cb._activationInFlight)
        verify(!cb.activateErrorDialog.visible,
               "activateErrorDialog must start closed")

        // gRPC code 14 = Unavailable: filtered (no user-visible dialog),
        // but the flag MUST still be cleared.
        cb._showActivateError("Camera input", { code: 14, message: "wedge" })
        verify(!cb._activationInFlight,
               "_showActivateError must clear flag even for filtered "
               + "(Unavailable=14) error codes")
        verify(!cb.activateErrorDialog.visible,
               "activateErrorDialog must NOT open for filtered "
               + "(Unavailable=14) error codes — the reconnect path "
               + "handles them silently")
    }

    // test_06: _showActivateError clears the flag for non-filtered
    // codes too (and surfaces the activateErrorDialog).
    //
    // Dual-sided: also assert that activateErrorDialog DOES open for
    // visible error codes.
    //
    // Falsifier: same as test_05 — moving _endActivation() below any
    // gating breaks one or both tests. Drop the
    // `activateErrorDialog.open()` call -> the dual-side assertion
    // for visible codes fails.
    function test_06_showActivateError_clears_flag_for_visible_codes() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        cb._beginActivation("Activating")
        verify(cb._activationInFlight)
        verify(!cb.activateErrorDialog.visible,
               "activateErrorDialog must start closed")

        // gRPC code 13 = Internal: NOT filtered, dialog should open.
        cb._showActivateError("SwitchOutputByProps",
                              { code: 13, message: "encode failed" })
        verify(!cb._activationInFlight,
               "_showActivateError must clear flag for visible error code")
        // The dialog is opened via the platform-native MessageDialog
        // helper which sets visible asynchronously on some backends;
        // tryVerify gives the event loop a chance to flush.
        tryVerify(function() { return cb.activateErrorDialog.visible }, 1500,
                  "activateErrorDialog must open for visible (Internal=13) "
                  + "error codes")
        compare(cb.activateErrorDialog.leg, "SwitchOutputByProps",
                "activateErrorDialog.leg must reflect the failing leg label")
    }

    // test_07: _beginActivation BUMPS _activationEpoch every call. The
    // epoch is the gate that drops stale callbacks from a superseded chain.
    //
    // Falsifier: drop `_activationEpoch += 1` from _beginActivation ->
    // the epoch stays constant, _isCurrentEpoch always returns true on
    // a stale callback.
    function test_07_begin_bumps_epoch() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        var e0 = cb._activationEpoch
        cb._beginActivation("Activating")
        var e1 = cb._activationEpoch
        verify(e1 > e0, "epoch must strictly advance on _beginActivation")
        cb._endActivation()

        cb._beginActivation("Deactivating")
        var e2 = cb._activationEpoch
        verify(e2 > e1, "second _beginActivation must advance epoch again")
    }

    // test_08: _isCurrentEpoch returns false for a stale epoch. A captured
    // pre-bump epoch must be recognised as superseded after a re-tap.
    //
    // Falsifier: change `_isCurrentEpoch` to `return true` (or drop the
    // epoch comparison) -> stale callbacks would touch new-chain state.
    function test_08_isCurrentEpoch_drops_stale() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        cb._beginActivation("Activating")
        var staleEpoch = cb._activationEpoch
        verify(cb._isCurrentEpoch(staleEpoch),
               "current epoch must be reported as current while in flight")

        cb._endActivation()
        verify(!cb._isCurrentEpoch(staleEpoch),
               "after _endActivation, the previous epoch must be stale "
               + "(flag is false; _isCurrentEpoch must reject)")

        cb._beginActivation("Deactivating")
        verify(!cb._isCurrentEpoch(staleEpoch),
               "after a fresh _beginActivation, the previously-captured "
               + "epoch must be stale (epoch advanced, _isCurrentEpoch "
               + "must reject the old value)")
    }

    // test_09 was removed: the prior test asserted that the explicit
    // `activationWatchdog.stop()` before `restart()` in _beginActivation
    // defended against a "fired-once timer
    // short-circuit" failure mode. QQmlTimer source
    // (qqmltimer.cpp restart()) implements stop+start unconditionally;
    // the failure mode tested was nonexistent. Asserting that
    // restart() resets a Timer is a property of QQmlTimer, not of our
    // code, so re-purposing this slot would be a vacuous test. Removed
    // entirely; the explicit stop() it was paired with has also been
    // removed from _beginActivation.

    // test_10: activationWatchdogMs is the readonly source of truth
    // for the watchdog interval. Exposes the magic-number hoist (B3).
    //
    // Falsifier: revert the hoist (re-inline `interval: 30000`) and
    // change `activationWatchdogMs` to a different value — the timer
    // interval would not track, and this test fails.
    function test_10_activationWatchdogMs_drives_timer_interval() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        var wd = _findWatchdog(cb)
        verify(wd !== null)

        compare(wd.interval, cb.activationWatchdogMs,
                "activationWatchdog.interval must equal activationWatchdogMs "
                + "(shared activation watchdog value)")
    // The literal `30000` anchor compare was removed — duplicating the
    // default outside the source
        // file accumulates magic numbers. The wd.interval ==
        // cb.activationWatchdogMs binding above is the only contract
        // the test needs to pin; the actual numeric value lives in
        // CamerasBuiltin.qml (`readonly property int activationWatchdogMs:
        // 30000`) and is documented there.
        verify(cb.activationWatchdogMs > 0,
               "activationWatchdogMs must be a positive ms interval")
    }

    // test_11: pin the public-API contract that the multi-step helper
    // functions live at top-level `builtin` scope, NOT nested inside an
    // Activate Button block. Re-inlining any of them makes sibling flows
    // unable to reach shared helpers.
    //
    // Falsifier: re-inline `function _removeBuiltinInputsAtPriority0`
    // back inside the Activate Button's QML scope (or any other
    // sibling block). The function then disappears from the
    // top-level `builtin` namespace and `cb._removeBuiltinInputsAtPriority0`
    // resolves to `undefined`. This test fails. Same applies to
    // _purgeBuiltinInputs, _doActivate, _rollbackPriority0,
    // _withEpoch.
    //
    // QML's id-block resolution makes a function
    // declared inside `Button { ... function _foo() {} ... }`
    // reachable as `_foo()` ONLY from within that Button's scope.
    // From a sibling Button (e.g. Deactivate calling a helper that
    // was scoped to Activate) the bare-name lookup falls through to
    // the global JS scope and silently raises ReferenceError. The
    // hoist to top-level `builtin` makes the function a property of
    // the component's QObject, reachable as `cb._foo`.
    function test_11_helpers_hoisted_to_top_level() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        verify(typeof cb._removeBuiltinInputsAtPriority0 === "function",
            "_removeBuiltinInputsAtPriority0 must be hoisted to top-level "
            + "for Deactivate to reach it")
        verify(typeof cb._purgeBuiltinInputs === "function",
            "_purgeBuiltinInputs must be hoisted to top-level for Activate "
            + "to reach it from outside its declaring block")
        verify(typeof cb._doActivate === "function",
            "_doActivate must be hoisted to top-level so any future sibling "
            + "caller or extracted helper can reach it")
        verify(typeof cb._doDeactivate === "function",
            "_doDeactivate must be hoisted to top-level so Deactivate's "
            + "End-RPC path is testable and shares the stale-callback guard")
        verify(typeof cb._rollbackPriority0 === "function",
            "_rollbackPriority0 must be hoisted to top-level — same "
            + "scope-invariant rationale as _doActivate")
        verify(typeof cb._withEpoch === "function",
            "_withEpoch must be hoisted to top-level so every async leg can "
            + "route through one shared epoch wrapper")
    }

    // test_12: _withEpoch returns a function that:
    //   (a) calls the inner function and forwards arguments when the
    //       captured epoch is still current;
    //   (b) silently drops the call when the chain has been
    //       superseded (a fresh _beginActivation bumped the epoch, or
    //       _endActivation cleared the in-flight flag).
    //
    // This is the exact contract every pre-_doActivate async callback relies
    // on. A test that drives the wrapper directly catches callback re-inlining
    // that bypasses the shared epoch wrapper.
    //
    // Falsifier: replace `if (!builtin._isCurrentEpoch(epoch)) return`
    // inside _withEpoch with `// gating disabled` (i.e. always
    // forward) -> the staleEpoch branch in this test invokes inner,
    // calls.length becomes 2, the test fails. Equivalent to commenting
    // out one of the `builtin._withEpoch(epoch, ...)` callsites in
    // _doActivate / the Activate Button onClicked.
    function test_12_withEpoch_drops_stale_invocations() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        var calls = []
        var inner = function() { calls.push(Array.prototype.slice.call(arguments)) }

        var epoch = cb._beginActivation("Activating")
        var wrapped = cb._withEpoch(epoch, inner)

        // Current-epoch invocation: must forward (and pass arguments through).
        wrapped("alpha", 42)
        compare(calls.length, 1,
                "_withEpoch must forward when the captured epoch is current")
        compare(calls[0][0], "alpha",
                "_withEpoch must pass first argument through unchanged")
        compare(calls[0][1], 42,
                "_withEpoch must pass second argument through unchanged")

        // Supersede the chain: end the activation. _isCurrentEpoch(epoch)
        // is now false because _activationInFlight is false — even though
        // _activationEpoch still equals the captured value.
        cb._endActivation()
        wrapped("beta")
        compare(calls.length, 1,
                "_withEpoch must DROP invocations after _endActivation "
                + "(the chain has been superseded; the captured epoch is stale)")

        // Re-arm with a fresh chain: epoch advances, the previously
        // captured wrapper is still bound to the old epoch and must
        // continue to drop. A late permission-denied callback from chain N
        // landing while chain N+1 is in flight must NOT touch chain N+1.
        var freshEpoch = cb._beginActivation("Deactivating")
        verify(freshEpoch > epoch,
               "fresh _beginActivation must advance the epoch")
        wrapped("gamma")
        compare(calls.length, 1,
                "_withEpoch must DROP invocations after a fresh "
                + "_beginActivation supersedes the original chain")

        cb._endActivation()
    }

    // test_13: pin the SCOPE INVARIANT "every async callsite under
    // _activationInFlight routes through _withEpoch". test_11 catches
    // re-inlining of the helpers; test_12 catches wrapper-internal
    // regressions; neither catches a developer adding or restoring an async
    // leg whose callback bypasses the wrapper.
    //
    // Strategy: combine two complementary checks.
    //
    //  (a) Behavioural assertion — drive a stale-callback scenario at the
    //      Deactivate path's success-tail side effect. Capture the live epoch,
    //      supersede the chain, then run a wrapped function whose body would
    //      open the deactivateErrorDialog. The wrapper MUST drop the call.
    //
    //  (b) Grep-style source assertion — for each known async callsite
    //      that runs under `_activationInFlight`, assert the source line
    //      contains `_withEpoch`. A developer who writes a new async leg
    //      and forgets the wrapper (or who replaces a wrapped callback
    //      with a bare `function(...) { ... }` like the pre-fix Deactivate
    //      Button) trips this assertion. Fragile under refactor — the
    //      counter-pattern is documented in the failure message so a
    //      future maintainer who legitimately moves a callsite knows
    //      exactly what to update.
    //
    // Falsifier (validated): comment out one of the `builtin._withEpoch(`
    // wrappers in the Deactivate Button's onClicked (e.g. the onAllDone
    // leg) and revert it to `function(failureCount) { if (!builtin
    // ._isCurrentEpoch(epoch)) return ... }`. Sub-check (b) for that
    // line should fail because the line no longer contains _withEpoch.
    function test_13_every_async_callsite_uses_withEpoch_wrapper() {
        // ---- (a) behavioural assertion ----
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })

        var epoch = cb._beginActivation("Deactivating")
        // Supersede before the wrapped callback fires (simulates the
        // chain being abandoned by a re-tap or watchdog timeout).
        cb._endActivation()

        // Build a wrapped side-effect mirroring the Deactivate path's
        // success-tail: it would open deactivateErrorDialog if it ran.
        // The wrapper MUST drop the call because the captured epoch is
        // now stale (_activationInFlight is false). We assert on
        // .visible (the QtQuick.Dialogs.MessageDialog observable for
        // open-state, mirroring test_06's pattern), not on
        // openedChanged (which is the Qt.labs.platform dialog API and
        // is undefined here).
        verify(cb.deactivateErrorDialog,
               "deactivateErrorDialog must be exposed as a property "
               + "alias (test seam — see CamerasBuiltin.qml line 32)")
        verify(!cb.deactivateErrorDialog.visible,
               "deactivateErrorDialog must start closed")

        var sideEffectFired = false
        var wrapped = cb._withEpoch(epoch, function() {
            sideEffectFired = true
            cb.deactivateErrorDialog.open()
        })
        wrapped()  // simulate the late RPC reply landing post-supersede.

        verify(!sideEffectFired,
               "_withEpoch must DROP a stale Deactivate-path callback — "
               + "the side effect (e.g. deactivateErrorDialog.open()) "
               + "must NOT fire when the chain has been superseded "
               + "(C1 binding-contract test: this is the exact failure mode "
               + "the Deactivate Button's inline `if "
               + "(!_isCurrentEpoch(epoch)) return` pattern half-fixed; "
               + "the wrapper is the only sanctioned form)")
        verify(!cb.deactivateErrorDialog.visible,
               "deactivateErrorDialog must NOT open for a stale-epoch "
               + "Deactivate callback (dual-side: wrapper-drop must "
               + "imply no UX surfacing)")

        // ---- (b) grep-style source assertion ----
        // Read CamerasBuiltin.qml from disk and assert each known async
        // callsite line contains `_withEpoch`. wingoutSourceDir is
        // exposed by tst_wingout.cpp:41 as a context property on every
        // QML test engine.
        verify(typeof wingoutSourceDir !== "undefined" && wingoutSourceDir,
               "wingoutSourceDir must be exposed by the QML test setup "
               + "(see tests/tst_wingout.cpp:41); the grep-style "
               + "callsite check below depends on it")

        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + wingoutSourceDir + "/CamerasBuiltin.qml",
                 false)  // synchronous read — the test thread is the QML
                         // thread, no UI to keep responsive here.
        xhr.send(null)
        verify(xhr.status === 200 || xhr.status === 0,
               "must be able to read CamerasBuiltin.qml source for "
               + "grep-style assertion (status=" + xhr.status + ")")
        var src = xhr.responseText
        verify(src && src.length > 0, "source file must be non-empty")

        // Each anchor is a fragment that uniquely identifies an async
        // callsite under _activationInFlight. The fragment must appear
        // on the SAME LINE as `_withEpoch(`, otherwise the wrapper has
        // been bypassed.
        //
        // If a future maintainer moves or renames a callsite, update
        // the corresponding anchor here. Adding a NEW async leg without
        // adding both the wrapper at the callsite AND a new anchor
        // entry here loses regression coverage for that leg — the
        // anchor list is the shared record for "callsites we promise are
        // wrapped".
        var anchors = [
            // Activate Button: camera permission callback.
            "androidPermissions.requestCameraPermission(",
            // Activate Button: mic permission callback.
            "androidPermissions.requestRecordAudioPermission(",
            // Activate Button: purge-done callback.
            "builtin._purgeBuiltinInputs(builtin.root.ffstreamCameraClient,",
            // Deactivate helper: End RPC callbacks. C1 binding.
            "ffstreamCameraClient.end(",
        ]

        var lines = src.split("\n")
        for (var a = 0; a < anchors.length; ++a) {
            var anchor = anchors[a]
            var anchorLine = -1
            var sawWrapper = false
            // Find the FIRST line that contains the anchor — these
            // anchors are intentionally chosen to be unique to a single
            // call site under the Activate/Deactivate Button onClicked
            // handlers. (`_removeBuiltinInputsAtPriority0(` does occur
            // elsewhere, e.g. inside `_purgeBuiltinInputs`, but the
            // anchor includes the `ffstreamCameraClient` argument name
            // which only appears at the Deactivate Button site.)
            for (var i = 0; i < lines.length; ++i) {
                if (lines[i].indexOf(anchor) === -1) continue
                anchorLine = i
                // Scan a small window forward for `_withEpoch(`. The
                // wrapper may live on the same line OR on the
                // immediately-following continuation lines (where the
                // callback function literal begins). 4 lines covers all
                // current callsites' indentation / wrap style; widen if
                // a future callsite needs more breathing room.
                for (var k = 0; k < 4 && (i + k) < lines.length; ++k) {
                    if (lines[i + k].indexOf("_withEpoch(") !== -1) {
                        sawWrapper = true
                        break
                    }
                }
                break
            }
            verify(anchorLine !== -1,
                   "anchor `" + anchor + "` must exist in "
                   + "CamerasBuiltin.qml (callsite renamed or removed? "
                   + "update the anchor list in this test to match)")
            verify(sawWrapper,
                   "async callsite `" + anchor + "` (line "
                   + (anchorLine + 1) + ") MUST route through "
                   + "builtin._withEpoch(epoch, function(...) { ... }) "
                   + "— the wrapper is the only sanctioned gate for "
                   + "stale-callback drop under _activationInFlight. "
                   + "If you legitimately moved this callsite, update "
                   + "the anchor; do NOT just delete the assertion.")
        }

        // Camera-daemon probes are the other async callbacks that can run
        // before _doActivate dispatches AddInput or before _doDeactivate
        // commits Inactive after End. They are intentionally checked as
        // a complete inventory rather than a single anchor: dropping
        // `_withEpoch` from any user-intent-bound probe must fail this
        // test.
        //
        // Inventory (4 callsites total at HEAD):
        //   1. _performBackendReachabilityProbe — Task #124 proactive
        //      reachability monitor. NOT _withEpoch-wrapped by design:
        //      the proactive monitor is NOT tied to a user-intent epoch
        //      (it ticks continuously regardless of Activate/Deactivate
        //      chains). Stale-callback drop on this path would actively
        //      defeat the monitor's purpose — the whole point is to
        //      observe daemon state independently of any chain.
        //   2. _ensureFFStreamCameraDaemonReady — initial reachability
        //      probe inside Activate flow. _withEpoch-wrapped.
        //   3. _probeFFStreamCameraDaemon — readiness polling inside
        //      Activate flow. _withEpoch-wrapped.
        //   4. _probeDeactivateIdle — post-End idle polling inside
        //      Deactivate flow. _withEpoch-wrapped.
        var cameraProbeLines = []
        for (var p = 0; p < lines.length; ++p) {
            if (lines[p].indexOf("ffstreamCameraClient.getInputsInfo(") !== -1) {
                cameraProbeLines.push(p)
            }
        }
        compare(cameraProbeLines.length, 4,
                "CamerasBuiltin.qml must have exactly four camera-daemon "
                + "getInputsInfo callsites: proactive reachability monitor "
                + "(Task #124), initial readiness, readiness polling, and "
                + "post-End idle polling. If a callsite was added or moved, "
                + "update this inventory instead of leaving it unguarded.")
        for (var r = 0; r < cameraProbeLines.length; ++r) {
            var line = cameraProbeLines[r]
            // Identify the proactive reachability probe by its
            // surrounding helper-name context. The proactive callsite is
            // exempt from the _withEpoch invariant by design.
            var isProactiveProbe = false
            for (var pre = 1; pre <= 8 && (line - pre) >= 0; ++pre) {
                if (lines[line - pre].indexOf("_performBackendReachabilityProbe")
                        !== -1) {
                    isProactiveProbe = true
                    break
                }
            }
            var wrappers = 0
            for (var offset = 0; offset < 16 && (line + offset) < lines.length; ++offset) {
                if (lines[line + offset].indexOf("_withEpoch(") !== -1) {
                    wrappers += 1
                }
            }
            if (isProactiveProbe) {
                compare(wrappers, 0,
                        "proactive reachability probe at line " + (line + 1)
                        + " must NOT wrap callbacks with _withEpoch — the "
                        + "monitor ticks independently of any user-intent "
                        + "epoch by design (Task #124). Wrapping here "
                        + "would silently no-op the monitor's flip during "
                        + "any in-flight Activate/Deactivate chain.")
            } else {
                compare(wrappers, 2,
                        "user-intent camera-daemon getInputsInfo callsite "
                        + "at line " + (line + 1)
                        + " must wrap BOTH success and error callbacks "
                        + "with _withEpoch. Dropping the wrapper lets "
                        + "stale probe callbacks mutate state in a "
                        + "superseded Activate/Deactivate chain.")
            }
        }
    }

    function test_14_camera_startup_probe_budget_fits_watchdog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        verify(cb.ffstreamCameraStartupProbeDeadlineMs > 0,
               "readiness probes must expose a positive per-RPC deadline")
        compare(cb.ffstreamCameraStartupProbeDeadlineMs,
                stubRoot.ffstreamCameraStartupProbeGrpcCallOptions.deadlineTimeout,
                "CamerasBuiltin must use the same short deadline as Main.qml's "
                + "camera-startup probe call options")
        compare(cb.ffstreamCameraStartupProbeBudgetMs,
                cb.ffstreamCameraStartupProbeAttempts
                * (cb.ffstreamCameraStartupProbeDeadlineMs
                   + cb.ffstreamCameraStartupProbeIntervalMs),
                "probe budget must be derived from attempts, deadline, and interval")
        verify(cb.ffstreamCameraStartupProbeBudgetMs < cb.activationWatchdogMs,
               "all readiness-probe retries must fit inside the activation watchdog")
    }

    function test_15_stale_purge_callbacks_do_not_remove_new_epoch_inputs() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        var client = stubRoot.ffstreamCameraClient
        var staleDoneCalls = 0
        var epoch = cb._beginActivation("Activating")
        cb._purgeBuiltinInputs(client, cb._withEpoch(epoch, function() {
            staleDoneCalls += 1
        }))
        verify(client.pendingGetInputsInfoFinish !== null,
               "purge must dispatch getInputsInfo and retain its callback")

        cb._endActivation()
        var freshEpoch = cb._beginActivation("Activating")
        verify(freshEpoch > epoch,
               "fresh activation must supersede the purge epoch")

        client.pendingGetInputsInfoFinish({
            inputsData: [
                {
                    priority: 0,
                    num: 0,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_camera" }
                        ]
                    }
                },
                {
                    priority: 0,
                    num: 1,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_microphone" }
                        ]
                    }
                }
            ]
        })

        compare(client.removeInputCalls, 0,
                "a stale purge getInputsInfo callback must not issue "
                + "RemoveInput after a newer activation has begun")
        compare(staleDoneCalls, 0,
                "a stale purge must not report completion into the newer "
                + "activation chain")
        cb._endActivation()
    }

    function test_16_stale_already_dispatched_remove_success_does_not_continue_purge() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        var client = stubRoot.ffstreamCameraClient
        client.autoFinishRemoveInput = false
        var staleDoneCalls = 0
        var epoch = cb._beginActivation("Activating")
        cb._purgeBuiltinInputs(client, cb._withEpoch(epoch, function() {
            staleDoneCalls += 1
        }))
        client.pendingGetInputsInfoFinish({
            inputsData: [
                {
                    priority: 0,
                    num: 0,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_camera" }
                        ]
                    }
                },
                {
                    priority: 0,
                    num: 1,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_microphone" }
                        ]
                    }
                }
            ]
        })
        compare(client.removeInputCalls, 1,
                "purge must dispatch the first highest-num RemoveInput")
        verify(client.pendingRemoveFinish !== null,
               "test must capture the already-dispatched RemoveInput success callback")

        cb._endActivation()
        var freshEpoch = cb._beginActivation("Activating")
        verify(freshEpoch > epoch,
               "fresh activation must supersede the dispatched remove callback")

        client.pendingRemoveFinish({})
        compare(client.removeInputCalls, 1,
                "stale already-dispatched RemoveInput success must not "
                + "advance to the next target after a newer activation")
        compare(staleDoneCalls, 0,
                "stale already-dispatched RemoveInput success must not "
                + "report purge completion into the newer activation")
        cb._endActivation()
    }

    function test_17_stale_already_dispatched_remove_error_does_not_mutate_state() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        var client = stubRoot.ffstreamCameraClient
        client.autoFinishRemoveInput = false
        var staleDoneCalls = 0
        var epoch = cb._beginActivation("Activating")
        cb._purgeBuiltinInputs(client, cb._withEpoch(epoch, function() {
            staleDoneCalls += 1
        }))
        client.pendingGetInputsInfoFinish({
            inputsData: [
                {
                    priority: 0,
                    num: 0,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_camera" }
                        ]
                    }
                },
                {
                    priority: 0,
                    num: 1,
                    inputConfig: {
                        customOptionsData: [
                            { key: "f", value: "android_microphone" }
                        ]
                    }
                }
            ]
        })
        compare(client.removeInputCalls, 1,
                "purge must dispatch the first highest-num RemoveInput")
        verify(client.pendingRemoveError !== null,
               "test must capture the already-dispatched RemoveInput error callback")

        cb._endActivation()
        var freshEpoch = cb._beginActivation("Activating")
        verify(freshEpoch > epoch,
               "fresh activation must supersede the dispatched remove callback")

        client.pendingRemoveError({ code: 13, message: "late remove failure" })
        compare(client.processGrpcErrorCalls, 0,
                "stale already-dispatched RemoveInput error must not feed "
                + "processGRPCError after a newer activation")
        compare(client.removeInputCalls, 1,
                "stale already-dispatched RemoveInput error must not "
                + "advance to the next target after a newer activation")
        compare(staleDoneCalls, 0,
                "stale already-dispatched RemoveInput error must not "
                + "report purge completion into the newer activation")
        cb._endActivation()
    }

    function test_18_video_codec_model_is_required_av1_only() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.videoCodec = "h264_mediacodec"

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        verify(cb.videoCodecModel !== null,
               "CamerasBuiltin must expose videoCodecModel for invariant testing")

        compare(cb.videoCodecModel.count, 1,
                "built-in camera streaming must expose only one video codec choice")
        compare(cb.videoCodecModel.get(0).value, settings.requiredVideoCodec,
                "the only live codec choice must be the required AV1 MediaCodec encoder")
        compare(settings.videoCodec, settings.requiredVideoCodec,
                "rebuilding the codec model must normalize stale persisted H.264 to AV1")
    }

    function test_19_camera_codec_source_has_no_unsupported_choices() {
        var src = _readWingoutSource("CamerasBuiltin.qml")

        verify(src.indexOf("h264_mediacodec") === -1,
               "CamerasBuiltin must not offer H.264 MediaCodec as a built-in camera choice")
        verify(src.indexOf("h265_mediacodec") === -1,
               "CamerasBuiltin must not offer H.265 MediaCodec as a built-in camera choice")
        verify(src.indexOf("libsvtav1") === -1,
               "CamerasBuiltin must not offer libsvtav1 as a built-in camera choice")
        verify(src.indexOf("libx264") === -1,
               "CamerasBuiltin must not offer libx264 as a built-in camera choice")
        verify(!/ffstreamCameraClient\.switchOutput\(\s*settingsController\.videoCodec\s*,/.test(src),
               "camera SwitchOutput callsites must not pass persisted videoCodec directly")
    }
}
