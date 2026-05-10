import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests for CamerasBuiltin.qml proactive gRPC backend reachability monitor
/// (Task #124, F-task116-3).
///
/// Falsifier intent: when the ffstreamCameraClient cannot reach the
/// ffstream-camera daemon for longer than a debounce grace window (2 s in
/// production), CamerasBuiltin must (1) flip `_backendReachable` to false,
/// (2) surface a dedicated error dialog identifying the missing supervisor,
/// (3) drive the Activate Button's `enabled` binding to false until the
/// channel attaches again. Pre-fix behaviour: Activate stayed enabled while
/// "qt.grpc : No channel(s) attached" flooded the logcat, the user-visible
/// Activate tap fired the multi-leg gRPC chain into the void with no UI
/// feedback (Task #116 RC report).
///
/// Strategy: instantiate CamerasBuiltin with a stub root that exposes a
/// controllable `ready` flag on the `ffstreamCameraClient` stub. The stub's
/// `getInputsInfo` answers each probe according to that flag. The proactive
/// monitor's probe interval and unreachable-grace are exposed as test seams
/// (`_grpcProbeIntervalMs`, `_grpcUnreachableGraceMs`) so the suite runs
/// without multi-second real-time waits while still exercising the live
/// Qt Timer machinery (i.e. tests cover the actual production code path,
/// not a count-based stand-in).
TestCase {
    id: tc
    name: "CamerasBuiltinGrpcNoChannel"
    when: windowShown
    width: 540
    height: 960

    // Mirrors tst_cameras_builtin_deactivate.qml's stub. Identical surface
    // is preserved so future fixture-unification (Task #13 follow-up) can
    // hoist these stubs into a shared helper.
    Component {
        id: rootStub
        QtObject {
            id: rootObject
            property QtObject grpcCallOptions: QtObject {
                property int deadlineTimeout: 10000
            }
            property QtObject ffstreamCameraStartupProbeGrpcCallOptions: QtObject {
                property int deadlineTimeout: 400
            }
            property QtObject ffstreamCameraReachabilityProbeGrpcCallOptions: QtObject {
                property int deadlineTimeout: 800
            }
            property string ffstreamCameraHost: "http://127.0.0.1:3594"
            // Test-controllable publisher URL: lets test_07 drive the
            // outputURL-empty-guard branch by setting cameraPublisherUrl=""
            // before instantiating CamerasBuiltin. Default keeps the
            // existing tests' assumption that a valid URL is configured.
            property string cameraPublisherUrl: "rtmp://127.0.0.1:1946/test/${v:0:codec}${a:0:codec}"
            function builtinCameraPublisherUrl() {
                return cameraPublisherUrl
            }
            property int startFFStreamCameraDaemonCalls: 0
            property var callOrder: []
            function startFFStreamCameraDaemon() {
                callOrder.push("unexpected-start")
                startFFStreamCameraDaemonCalls += 1
                return false
            }
            property QtObject streamingSettings: QtObject {
                property bool active: false
                property int width: 1920
                property int height: 1920
                property int fps: 30
                property int bitrateKbps: 4000
                property int maxBitrateKbps: 8000
                readonly property string missionVideoCodec: "av1_mediacodec"
                property string videoCodec: "av1_mediacodec"
                property string audioCodec: "aac"
                property int audioSampleRate: 48000
                property int audioBitrateKbps: 64
                property int audioChannels: 1
                property string outputUrl: ""
                property string preferredCamera: "Front"
                property int preferredMicrophoneId: 0
                property int userIntentEpoch: 0
                property int activeCameraNum: -1
                property int activeMicrophoneNum: -1
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
                property bool ready: true
                property int getInputsInfoCalls: 0
                property int processGrpcErrorCalls: 0
                property int addInputCalls: 0
                property int setOutputUrlCalls: 0
                property int switchOutputCalls: 0
                property int removeInputCalls: 0
                property int endCalls: 0
                property var probeOptionDeadlines: []
                function isChannelReady() { return ready }
                function setServerUri(_) {}
                function processGRPCError(_) { processGrpcErrorCalls += 1 }
                function getInputsInfo(finishCallback, errorCallback, _options) {
                    getInputsInfoCalls += 1
                    probeOptionDeadlines.push(_options && _options.deadlineTimeout !== undefined
                                              ? _options.deadlineTimeout : -1)
                    if (ready) {
                        finishCallback({ inputs: [] })
                        return
                    }
                    errorCallback({ code: 14, message: "daemon unavailable" })
                }
                function removeInput(_, _, _, _, _) { removeInputCalls += 1 }
                function addInput(_priority, _url, _customOptions, finishCallback, _errorCallback, _options) {
                    addInputCalls += 1
                    finishCallback({ num: 0 })
                }
                function setOutputUrl(_url, finishCallback, _errorCallback, _options) {
                    setOutputUrlCalls += 1
                    finishCallback({})
                }
                function switchOutput(
                    _videoCodec, _width, _height, _videoBitrate,
                    _audioCodec, _audioSampleRate, _audioBitrate,
                    _maxBitrate, finishCallback, _errorCallback, _options) {
                    switchOutputCalls += 1
                    finishCallback({})
                }
                function end(finishCallback, _errorCallback, _options) {
                    endCalls += 1
                    finishCallback({})
                }
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

    // Helper: instantiate CamerasBuiltin with the test seam values that
    // collapse the proactive monitor's wall-clock cadence so the suite runs
    // without multi-second real-time waits. Production defaults (1 s probe,
    // 2 s grace) remain in CamerasBuiltin.qml; only the test overrides.
    // 50 ms probe + 200 ms grace = ~4 probe ticks per grace window — wide
    // enough margin to avoid flake on slow CI but tight enough that the
    // suite finishes in well under 5 seconds.
    function makeBuiltin(stubRoot) {
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate with stub root")
        cb._grpcProbeIntervalMs = 50
        cb._grpcUnreachableGraceMs = 200
        return cb
    }

    // Locate the Activate / Re-Activate Button by traversing the rendered
    // tree by .text. CamerasBuiltin scopes ids file-locally so we cannot
    // reach the button via id from here. Returns null if not found, which
    // forces the calling test to fail explicitly (the button must exist
    // for AC#2 verification).
    function findActivateButton(cb) {
        var stack = [cb]
        while (stack.length > 0) {
            var node = stack.shift()
            if (node && typeof node.text === "string"
                    && (node.text === "Activate" || node.text === "Re-Activate")) {
                return node
            }
            if (node && node.children) {
                for (var i = 0; i < node.children.length; ++i) {
                    stack.push(node.children[i])
                }
            }
        }
        return null
    }

    // Broke-the-code-validation: this test catches a dual-sided regression
    // at startup. POSITIVE side: when the backend is reachable, the
    // implementation must NOT spuriously open the unreachable-dialog (catches
    // an eager-failure-handler regression where the dialog opens on the
    // FIRST tick before the grace window can suppress transient bring-up
    // noise). NEGATIVE side: the dialog must EXIST as an addressable alias
    // (catches a regression where the implementer forgets to wire the
    // property alias for test-introspection — the dialog could be present
    // in-tree but unreachable to assertions).
    function test_01_reachable_state_keeps_button_enabled_no_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        stubRoot.ffstreamCameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Allow at least two probe ticks plus the grace window to pass so
        // any spurious flip would have surfaced by now (50+50+200 = 300 ms;
        // wait 350 ms for margin).
        wait(350)

        compare(cb._backendReachable, true,
                "POSITIVE: initial reachable state must hold "
                + "_backendReachable=true throughout > 1 grace window")
        var dlg = cb.gRPCBackendUnreachableDialog || null
        verify(dlg !== null,
               "NEGATIVE-via-test-introspection: gRPCBackendUnreachableDialog "
               + "alias must be addressable for any later test to assert "
               + "visibility — missing alias would silently invalidate "
               + "tests 03 and 04 below")
        verify(!dlg.visible,
               "POSITIVE: no error dialog must surface when backend reachable")
        var activateButton = findActivateButton(cb)
        verify(activateButton !== null,
               "Activate button must exist in tree")
        compare(activateButton.enabled, true,
                "POSITIVE: Activate button must be enabled when "
                + "_backendReachable=true")
    }

    // Broke-the-code-validation: catches a missing or mis-thresholded grace
    // window. POSITIVE side: probe failures inside the grace must not
    // surface a UI flip (transient hiccups stay invisible). NEGATIVE side:
    // if the implementer forgot the debounce timer entirely and flipped
    // _backendReachable on the first probe failure, this test would fail
    // because the assertion sees the flag false within ~grace/4. Equally,
    // a zero grace would surface here.
    function test_02_unreachable_under_grace_keeps_reachable_true() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Allow first reachable probe to confirm baseline.
        tryVerify(function() { return cameraClient.getInputsInfoCalls >= 1 },
                  500, "at least one reachable probe must execute "
                  + "before flipping the stub")
        compare(cb._backendReachable, true,
                "baseline: initial reachable probe must hold "
                + "_backendReachable=true")

        cameraClient.ready = false
        // Wait < grace (test grace is 200 ms; sleep 80 ms — well inside).
        wait(80)

        compare(cb._backendReachable, true,
                "POSITIVE: probe failures inside the debounce grace must "
                + "NOT flip the reachability flag — the user expects "
                + "transient hiccups to stay invisible until the grace "
                + "window expires")
        var dlg = cb.gRPCBackendUnreachableDialog
        verify(!dlg.visible,
               "POSITIVE: dialog must stay closed inside the debounce grace")
    }

    // Broke-the-code-validation: this is THE acceptance gate for AC#1+#3.
    // POSITIVE side: probe failures persisting beyond grace MUST flip the
    // flag and open the dialog with actionable text. NEGATIVE side: the
    // dialog must be a DISCRETE dialog (separate alias from
    // cameraDaemonStoppedDialog and activateErrorDialog), since AC#3
    // requires a backend-unreachable-specific actionable message ("launch
    // supervisor") that differs from the existing reactive-on-tap error
    // paths. A common regression: the implementer extends existing
    // _ensureFFStreamCameraDaemonReady (reactive on Activate tap only)
    // without adding the proactive ticker, so backend-down state remains
    // invisible until the user taps Activate — that bug would leave
    // _backendReachable=true after >grace probe failures and fail here.
    function test_03_unreachable_over_grace_flips_flag_and_opens_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false

        var cb = makeBuiltin(stubRoot)

        // After grace (200 ms test override), the flag must flip and the
        // dialog must be visible. tryVerify polls so the success path
        // completes as soon as the flip happens, with 1500 ms ceiling for
        // slow CI.
        tryVerify(function() { return cb._backendReachable === false }, 1500,
                  "POSITIVE: probe failures persisting beyond the debounce "
                  + "grace must flip _backendReachable to false")
        var dlg = cb.gRPCBackendUnreachableDialog
        verify(dlg !== null && dlg !== undefined,
               "NEGATIVE-via-distinct-alias: gRPCBackendUnreachableDialog "
               + "must exist as a discrete dialog (NOT shared with "
               + "cameraDaemonStoppedDialog or activateErrorDialog — "
               + "distinct AC#3 actionable text)")
        tryVerify(function() { return dlg.visible }, 1500,
                  "POSITIVE: dialog must surface when backend unreachable "
                  + "persists beyond the grace window")
        verify(/supervisor/i.test(dlg.text),
               "POSITIVE/AC#3: dialog text must point user to launching the "
               + "supervisor — 'error message clear + actionable'. "
               + "Found text: " + dlg.text)
    }

    // Broke-the-code-validation: catches a missing recovery path. POSITIVE
    // side: a successful probe after persistent failures must clear the
    // flag and dismiss the dialog. NEGATIVE side: if the implementer adds
    // the proactive failure flip but forgets to clear the flag on a
    // successful probe, the dialog stays visible forever and Activate stays
    // disabled — a worse UX than no fix at all (user can't recover even
    // after restoring the daemon). This test enforces the recovery
    // semantics from the task body: "Enable Activate when channel attaches."
    function test_04_recovery_clears_flag_and_dismisses_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false

        var cb = makeBuiltin(stubRoot)

        // Step 1: drive into unreachable state.
        tryVerify(function() { return cb._backendReachable === false }, 1500,
                  "must reach unreachable state before testing recovery")
        var dlg = cb.gRPCBackendUnreachableDialog
        tryVerify(function() { return dlg.visible }, 1500,
                  "dialog must be visible before testing recovery")

        // Step 2: flip the stub back to reachable; the next probe tick must
        // observe the success and clear both the flag and the dialog.
        cameraClient.ready = true
        tryVerify(function() { return cb._backendReachable === true }, 1500,
                  "POSITIVE: successful probe after unreachable must flip "
                  + "_backendReachable back to true")
        tryVerify(function() { return !dlg.visible }, 1500,
                  "POSITIVE: dialog must auto-dismiss when channel "
                  + "re-attaches — user must not have to click OK to "
                  + "recover Activate")
        var activateButton = findActivateButton(cb)
        verify(activateButton !== null,
               "Activate button must exist in tree")
        tryVerify(function() { return activateButton.enabled === true }, 500,
                  "POSITIVE: Activate button must re-enable on recovery")
    }

    // Broke-the-code-validation: catches probe contention with an active
    // Activate chain. POSITIVE side: the proactive ticker must be silent
    // while _activationInFlight=true (the Activate flow already issues its
    // own getInputsInfo probe via _ensureFFStreamCameraDaemonReady plus
    // four more RPCs — AddInput x2, SetOutputURL, SwitchOutput). NEGATIVE
    // side: a continuously-firing proactive probe during
    // _activationInFlight==true would queue extra RPCs against the live
    // daemon, doubling round-trip pressure during the most latency-
    // sensitive moment of the UI and risking reorder bugs. The test asserts
    // the call counter does NOT advance across multiple test-tick intervals
    // while in_flight is held high.
    function test_05_proactive_probe_suspended_during_activation_in_flight() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Wait for first proactive probe so the baseline counter is non-zero.
        tryVerify(function() { return cameraClient.getInputsInfoCalls >= 1 },
                  500, "at least one proactive probe must execute before "
                  + "the suspension test starts")
        var baseline = cameraClient.getInputsInfoCalls

        // Begin activation — sets _activationInFlight=true. The proactive
        // ticker must stop firing for the duration. _beginActivation does
        // NOT itself dispatch RPCs, so any new getInputsInfo calls observed
        // below must come from the proactive path (the falsifier).
        cb._beginActivation("Activating")
        compare(cb._activationInFlight, true,
                "_beginActivation must set _activationInFlight=true")

        // Sleep across multiple test-tick intervals (50 ms probe interval,
        // 200 ms wait = up to 4 probes IF NOT suspended).
        wait(200)

        compare(cameraClient.getInputsInfoCalls, baseline,
                "POSITIVE: proactive probe must be suspended while "
                + "_activationInFlight is true — extra probes during the "
                + "Activate chain pollute round-trip latency budget and "
                + "risk reorder bugs (NEGATIVE: counter advancing here would "
                + "indicate the suspension predicate is missing)")

        // Cleanup: end activation so the ticker can resume for any later
        // tests in this case.
        cb._endActivation()
    }

    // Broke-the-code-validation: catches the AC#2 "Activate button DISABLED
    // when no-channel persists > 2s" surface as a LIVE Button.enabled
    // observation. POSITIVE side: a partial-fix that opens the dialog
    // (AC#1+#3) but forgets to gate Button.enabled would leave the user
    // tapping Activate and triggering the silent-failure path the task is
    // closing — this test inspects the live Button state to ensure the
    // binding actually flips, not just the state property. NEGATIVE side:
    // the test verifies the button's enabled becomes false ONLY when
    // _backendReachable is false (avoids a regression that hard-disables
    // the button regardless of state).
    function test_06_activate_button_disabled_when_backend_unreachable() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false

        var cb = makeBuiltin(stubRoot)

        // Wait for proactive monitor to register unreachable.
        tryVerify(function() { return cb._backendReachable === false }, 1500,
                  "monitor must flip _backendReachable to false")

        var activateButton = findActivateButton(cb)
        verify(activateButton !== null,
               "Activate button must be locatable in CamerasBuiltin tree")
        compare(activateButton.enabled, false,
                "POSITIVE/AC#2: Activate button must be disabled while "
                + "_backendReachable is false. Re-enables when channel "
                + "attaches (test_04 covers the recovery half).")
    }

    // Broke-the-code-validation: catches the configuration-error empty-URL
    // hole. POSITIVE side: Activate must REJECT (open dialog, dispatch zero
    // RPCs) when the publisher URL resolves to empty — the existing chain
    // would otherwise call setOutputUrl("") which the avd publisher regex
    // rejects mid-chain, leaving inputs registered but no output configured.
    // NEGATIVE side: the dialog must identify the missing field by name
    // ("Output URL" leg label) so the user can act, AND the in-flight cue
    // must clear so the user is not stuck with a permanent "Activating…"
    // state. Architectural reuse of the _showActivateConfigurationError
    // pattern (Task #124 Pool C re-author per coord disposition).
    function test_07_activate_rejects_missing_publisher_url_before_inputs() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true
        // Drive the empty-URL branch.
        stubRoot.cameraPublisherUrl = ""

        var cb = makeBuiltin(stubRoot)

        // Simulate a user tap by entering the in-flight state and
        // dispatching the activation chain — this mirrors the production
        // Activate Button onClicked flow's call sequence (without going
        // through the runtime-permissions prompts that the headless test
        // harness cannot grant).
        cb._beginActivation("Activating")
        cb._doActivate()

        // The empty-URL guard must reject before any AddInput / SetOutputUrl
        // / SwitchOutput dispatch. The readiness probe IS expected to fire
        // (the guard only fires after _ensureFFStreamCameraDaemonReady's
        // success callback) — so getInputsInfoCalls is allowed to be > 0.
        // What MUST be zero are the URL-dependent legs.
        compare(cameraClient.addInputCalls, 0,
                "POSITIVE: empty publisher URL must short-circuit BEFORE "
                + "the camera/microphone AddInput calls — otherwise inputs "
                + "register against an output URL that will be rejected "
                + "mid-chain")
        compare(cameraClient.setOutputUrlCalls, 0,
                "POSITIVE: empty publisher URL must NOT be sent to "
                + "ffstream-camera SetOutputURL — the avd publisher regex "
                + "rejects empty strings and the failure surfaces as a "
                + "wedged libav RTMP open inside the encoder pipeline")
        compare(cameraClient.switchOutputCalls, 0,
                "POSITIVE: empty publisher URL must NOT trigger "
                + "SwitchOutputByProps — the chain is invalid before this "
                + "leg")
        verify(!cb._activationInFlight,
               "POSITIVE: configuration-error path must clear the "
               + "in-flight cue so the user is not stranded with a "
               + "permanent 'Activating…' label")

        var dlg = cb.activateErrorDialog || null
        verify(dlg !== null,
               "NEGATIVE-via-test-introspection: activateErrorDialog "
               + "alias must be addressable")
        tryVerify(function() { return dlg.visible }, 1000,
                  "POSITIVE/AC#3-class: dialog must surface the empty-URL "
                  + "configuration error")
        compare(dlg.leg, "Output URL",
                "POSITIVE/AC#3-class: dialog must identify the missing "
                + "field by name so the user can act on it (NEGATIVE: a "
                + "generic 'configuration error' would force the user to "
                + "guess which field is missing)")
    }

    // Helper: count counters on the stub via initial properties.
    function _initCameraClientCounters(stub) {
        // Stubs already initialise these in their property declarations;
        // helper exists so future tests have a single point to extend if
        // counter set evolves.
        return {
            addInputCalls: stub.addInputCalls,
            setOutputUrlCalls: stub.setOutputUrlCalls,
            switchOutputCalls: stub.switchOutputCalls
        }
    }
}
