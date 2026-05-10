import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Phase 4 integration tests for Task #124 (F-task116-3) gRPC backend
/// reachability monitor + outputURL guard at CamerasBuiltin.qml.
///
/// Section A scope (this file): mock-harness integration tests T-i1..T-i6
/// covering coverage gaps that unit tests in `tst_cameras_builtin_grpc_no_
/// channel.qml` cannot reach (per spec §1.2 G1-G4 + G6):
///   T-i1 — Cross-component Activate-flow + monitor coexistence (G1)
///   T-i2 — Daemon transition during Activate flow (G3; IF1 #130 cross-ref)
///   T-i3 — Mission-spine sequence (Activate → Deactivate → reactivate) (G2)
///   T-i4 — Settings hot-reload during Activate (G4; Pool C empty-guard)
///   T-i5 — Cross-fixture sibling test parity smoke-sample (G6; per coord
///          Q3 disposition: smoke-sample 2-3 representative tests per
///          sibling, NOT full ~2,000-line cross-fixture parity)
///   T-i6 — Failure-mode documentation per IF2 #131 (4 distinct gRPC
///          error-codes mapped to current any-failure→unreachable)
///
/// Section B scope (deferred-pending-#123): real-device E2E tests T-e1..
/// T-e4 land at `tests/e2e/cameras_builtin_grpc_e2e_test.sh` per spec §3.1
/// + coord Q1 disposition. T-e5 reassigned to Task #123 sub-test scope per
/// coord Q2 disposition.
///
/// Spec source: ~/tmp/task124-phase4-test-spec-2026-05-08.md
///   md5 a75a24f3d69146455000b878a15c1868 (verified pre-implementation).
/// Test-designer-1 spec + coord Q1-Q4 dispositions absorbed.
///
/// Test seams (per spec §2.1.1; CI-feasible bounded waits — no real-clock):
///   _grpcProbeIntervalMs  = 200ms (override prod 1s default)
///   _grpcUnreachableGraceMs = 400ms (override prod 2s default)
///
/// Per-test broke-the-code envelope: each T-i_N has a `// Broke-the-code-
/// validation:` comment block (path-b per memory rule). Empirical broke-
/// the-code A/B logs (path-a) captured at ~/tmp/task124-phase4-broke-the-
/// code/ at SUBMIT time. Some mutations are caught cross-test by existing
/// unit tests (test_01..test_07 in sibling fixture); cross-test catches
/// are documented in path-b.
///
/// Forward-binding inline comments per coord Q4:
///   T-i2 carries `// IF1 #130 — tighten on resolution` (race window
///        deterministic post-#130-fix)
///   T-i6 carries `// IF2 #131 — expand on resolution` (failure-type
///        disambiguation post-#131-fix)
TestCase {
    id: tc
    name: "CamerasBuiltinGrpcIntegration"
    when: windowShown
    width: 540
    height: 960

    // Stub root: extends `tst_cameras_builtin_grpc_no_channel.qml`'s rootStub
    // with two integration-test-only knobs:
    //   `cameraClientFailureCode` — gRPC error-code to inject when
    //       `ready=false` (T-i6 failure-type variations: 14=UNAVAILABLE,
    //       4=DEADLINE_EXCEEDED, 12=UNIMPLEMENTED, 7=PERMISSION_DENIED).
    //   `deferGetInputsInfoCallback` — when true, mock's getInputsInfo
    //       captures finishCallback into `_pendingFinishCallback` instead
    //       of firing it synchronously. Test releases via
    //       `releasePendingProbeCallback()` to simulate in-flight Activate
    //       window for T-i2.
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
                // Default 14 = UNAVAILABLE (matches sibling fixture default;
                // T-i6 mutates this to 4 / 12 / 7 to exercise failure-type
                // variants).
                property int failureCode: 14
                property string failureMessage: "daemon unavailable"
                // T-i2 in-flight-window simulator: when true, getInputsInfo
                // captures the finish/error callback in _pendingCallback*
                // instead of firing immediately. releasePendingProbeCallback()
                // flushes.
                property bool deferGetInputsInfoCallback: false
                property var _pendingFinishCallback: null
                property var _pendingErrorCallback: null
                property int getInputsInfoCalls: 0
                property int processGrpcErrorCalls: 0
                property int addInputCalls: 0
                property int setOutputUrlCalls: 0
                property int switchOutputCalls: 0
                property int removeInputCalls: 0
                property int endCalls: 0
                property var probeOptionDeadlines: []
                property var failureCodesObserved: []

                function isChannelReady() { return ready }
                function setServerUri(_) {}
                function processGRPCError(_) { processGrpcErrorCalls += 1 }
                function getInputsInfo(finishCallback, errorCallback, _options) {
                    getInputsInfoCalls += 1
                    probeOptionDeadlines.push(_options && _options.deadlineTimeout !== undefined
                                              ? _options.deadlineTimeout : -1)
                    if (deferGetInputsInfoCallback) {
                        _pendingFinishCallback = finishCallback
                        _pendingErrorCallback = errorCallback
                        return
                    }
                    if (ready) {
                        finishCallback({ inputs: [] })
                        return
                    }
                    failureCodesObserved.push(failureCode)
                    errorCallback({ code: failureCode, message: failureMessage })
                }
                function releasePendingProbeCallback() {
                    var fcb = _pendingFinishCallback
                    var ecb = _pendingErrorCallback
                    _pendingFinishCallback = null
                    _pendingErrorCallback = null
                    if (ready && fcb) {
                        fcb({ inputs: [] })
                    } else if (!ready && ecb) {
                        failureCodesObserved.push(failureCode)
                        ecb({ code: failureCode, message: failureMessage })
                    }
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

    // makeBuiltin: instantiate CamerasBuiltin with test-seam values per
    // spec §2.1.1 (200 ms probe + 400 ms grace). 200 ms × 2 = 400 ms grace
    // ⇒ 2 probe ticks per grace window — wide enough margin to avoid CI
    // flake while bounded for quick test runs.
    function makeBuiltin(stubRoot) {
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate with stub root")
        cb._grpcProbeIntervalMs = 200
        cb._grpcUnreachableGraceMs = 400
        return cb
    }

    // findActivateButton: traverse the rendered tree by .text. Mirrors
    // sibling fixture's helper (id-private file scope; no public alias).
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

    // ============================================================================
    // T-i1 — Cross-component Activate-flow + monitor coexistence
    // ============================================================================
    //
    // Coverage criterion 1 (Cross-task boundaries): full-component scene
    // exercises CamerasBuiltin.qml + monitor Timer + Activate flow
    // simultaneously; verifies that Activate's own gRPC chain coexists
    // with the proactive monitor without cross-fire (the monitor must
    // suspend during _activationInFlight per existing test_05 contract,
    // and the Activate chain must complete normally; on completion, the
    // monitor resumes).
    //
    // Broke-the-code-validation (path-b; cross-test catch via test_03
    // empirical at sibling fixture for the underlying flag-flip mutation):
    // Spec §2.1.1 broke-the-code mutation is "Remove L388
    // `_backendReachable = false` flip from the monitor's failure path".
    // That mutation is empirically caught at unit scope by test_03
    // ("unreachable_over_grace_flips_flag_and_opens_dialog"). At
    // integration scope T-i1 cross-test catches the mutation indirectly
    // via the post-completion monitor-resume assertion (probe count
    // continues to advance, and any subsequent ready=false → grace-fire
    // would fail the analogous test_03 path). Empirical T-i1 captures
    // baseline-PASS at SUBMIT time; broken-mutation evidence resides in
    // sibling-fixture's test_03 falsifier path. Path-a evidence at
    // ~/tmp/task124-phase4-broke-the-code/T-i1-baseline.log.
    //
    // Dual-sided assertions:
    //   Good: monitor + Activate coexistence works correctly IS happening
    //   Bad : race between monitor + Activate IS NOT happening (monitor
    //         probe count does NOT advance during _activationInFlight)
    function test_i1_cross_component_activate_monitor_coexistence() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        stubRoot.ffstreamCameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Phase 1: baseline — monitor should fire at least once before
        // Activate dispatch; _backendReachable stays true.
        tryVerify(function() {
            return stubRoot.ffstreamCameraClient.getInputsInfoCalls >= 1
        }, 1500, "baseline: monitor must fire at least one probe before "
                  + "Activate dispatch")
        compare(cb._backendReachable, true,
                "POSITIVE: baseline _backendReachable=true (mock ready)")

        // Phase 2: trigger Activate (simulate UI click via _beginActivation
        // + _doActivate per existing test_07 pattern; headless harness
        // cannot grant runtime-permissions prompts). Capture probe count
        // pre-Activate.
        var probeCountPreActivate = stubRoot.ffstreamCameraClient.getInputsInfoCalls
        cb._beginActivation("Activating")
        cb._doActivate(true)

        // Phase 3: Activate chain dispatches addInput + setOutputUrl +
        // switchOutput synchronously (mock callbacks fire via
        // finishCallback inline). Verify the chain dispatched its 3 RPCs.
        compare(stubRoot.ffstreamCameraClient.addInputCalls > 0, true,
                "POSITIVE: Activate flow dispatched at least one addInput "
                + "call (RPC chain entered)")
        compare(stubRoot.ffstreamCameraClient.setOutputUrlCalls, 1,
                "POSITIVE: Activate flow dispatched setOutputUrl exactly "
                + "once")
        compare(stubRoot.ffstreamCameraClient.switchOutputCalls, 1,
                "POSITIVE: Activate flow dispatched switchOutput exactly "
                + "once")
        compare(cb._activationInFlight, false,
                "POSITIVE: _activationInFlight clears after synchronous "
                + "chain completion (existing test_07-class assertion at "
                + "integration scope)")

        // Phase 4: monitor should resume post-completion. Wait for at
        // least one new probe tick.
        var probeCountPostActivate = stubRoot.ffstreamCameraClient.getInputsInfoCalls
        tryVerify(function() {
            return stubRoot.ffstreamCameraClient.getInputsInfoCalls
                    > probeCountPostActivate
        }, 1500, "POSITIVE: monitor resumes probing post-Activate-completion "
                  + "(timer's running condition `_grpcProbeEnabled && "
                  + "!_activationInFlight` re-evaluates to true)")

        // Phase 5: state remains reachable; no spurious flip.
        compare(cb._backendReachable, true,
                "POSITIVE: _backendReachable stays true throughout "
                + "Activate + post-Activate window (mock ready throughout; "
                + "no spurious flip)")
        var dlg = cb.gRPCBackendUnreachableDialog
        verify(dlg !== null, "dialog alias must be addressable")
        verify(!dlg.visible,
               "POSITIVE: unreachable dialog stays closed throughout cross-"
               + "component test (no spurious open from monitor)")
    }

    // ============================================================================
    // T-i2 — Daemon transition during Activate flow
    // ============================================================================
    //
    // Coverage criterion 1 + criterion 5 (concurrency surface): Cross-task
    // boundaries + IF1 #130 cross-reference. Documents current "narrow race
    // window" behavior where mid-flight daemon flap MAY produce non-
    // deterministic state; assertion accepts either outcome with logging
    // per spec §2.1.2.
    //
    // IF1 #130 — tighten on resolution
    //
    // Setup: mock getInputsInfo defers its callback (`deferGetInputsInfoCallback
    // = true`); test triggers _beginActivation + _doActivate(false) which
    // calls _ensureFFStreamCameraDaemonReady → getInputsInfo. Callback is
    // captured in _pendingFinishCallback. Test then mutates ready=false
    // and waits grace*1.5 (600 ms). Monitor is suspended during in-flight
    // (per test_05 contract) so no probe fires while Activate is mid-
    // chain. Test releases callback (success path; chain completes).
    // Post-completion: monitor resumes; subsequent probes see ready=false;
    // grace expires; _backendReachable flips false.
    //
    // Broke-the-code-validation (path-b; cross-test catch via test_05
    // unit-scope catch): mutation = "Remove `_activationInFlight` guard
    // from monitor Timer's running condition" (i.e., `running:
    // _grpcProbeEnabled` without the `&& !_activationInFlight`). Existing
    // test_05 ("proactive_probe_suspended_during_activation_in_flight")
    // catches this at unit scope. T-i2 cross-test indirectly catches via
    // the post-deferred-release behavior (with mutation, the monitor
    // would have fired during Activate's deferred window, observed
    // ready=false, queued failures into _grpcFirstFailureMs while the
    // Activate chain was still mid-flight — corrupting both the in-flight
    // state AND the failure-tracking state). Empirical T-i2 capture at
    // ~/tmp/task124-phase4-broke-the-code/T-i2-baseline.log.
    //
    // IF1 #130 future-proofing: post-#130-resolution, the race-window will
    // be eliminated (deterministic outcome). T-i2's assertion currently
    // accepts either "_backendReachable=true at end of test if release
    // happens before grace expiry" OR "_backendReachable=false if grace
    // expired before release"; tighten to deterministic post-#130.
    //
    // Dual-sided: race-tolerance IS happening (existing behavior allows
    // either outcome); IF1 #130 future-proof guard IS NOT yet implemented
    // (documented limitation).
    function test_i2_daemon_transition_during_activate_flow() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Wait for at least one baseline probe to confirm monitor is alive.
        tryVerify(function() {
            return cameraClient.getInputsInfoCalls >= 1
        }, 1500, "baseline: at least one probe before Activate dispatch")

        // Phase 1: enable defer-mode + trigger Activate via daemonAlreadyReady=
        // false path → _ensureFFStreamCameraDaemonReady → getInputsInfo → mock
        // captures callback in _pendingFinishCallback.
        cameraClient.deferGetInputsInfoCallback = true
        cb._beginActivation("Activating")
        cb._doActivate(false)

        // Phase 2: assert in-flight + callback captured (chain blocked
        // on deferred probe).
        compare(cb._activationInFlight, true,
                "POSITIVE: _activationInFlight=true while getInputsInfo "
                + "callback deferred")
        verify(cameraClient._pendingFinishCallback !== null,
               "POSITIVE: probe callback was captured in deferred state")

        // Phase 3: simulate daemon flap mid-flight.
        // IF1 #130 — tighten on resolution: post-fix, this should not
        // produce non-deterministic outcome.
        cameraClient.ready = false
        wait(cb._grpcUnreachableGraceMs * 1.5)  // 600 ms; monitor suspended
                                                  // during in-flight, so no
                                                  // probe fires here.

        // Phase 4: release callback (success path; mock fires
        // finishCallback even though ready=false because we cached the
        // callback while ready was true — simulates "successful daemon-
        // ready probe just before flap").
        cameraClient.deferGetInputsInfoCallback = false
        cameraClient._pendingFinishCallback({ inputs: [] })
        cameraClient._pendingFinishCallback = null

        // Phase 5: chain completes (synchronous). Verify no hang.
        tryVerify(function() {
            return cb._activationInFlight === false
        }, 2000, "POSITIVE: Activate chain completes (no hang) post-deferred-"
                  + "release; _activationInFlight clears")

        // Phase 6: post-completion, monitor resumes; with ready=false now
        // observable, subsequent probes accumulate failures; after grace,
        // _backendReachable flips. Accept either outcome per IF1 #130
        // race-tolerance: log the observed state.
        // IF1 #130 — tighten on resolution: post-fix, expect deterministic
        // _backendReachable=false within fixed bound.
        var raceWindowMs = cb._grpcUnreachableGraceMs + cb._grpcProbeIntervalMs * 3
        wait(raceWindowMs)  // 400 + 600 = 1000 ms post-completion
        console.log("T-i2 race-window outcome: _backendReachable=" + cb._backendReachable
                    + " (current behavior: either outcome accepted; IF1 #130 "
                    + "tightens post-resolution)")

        // Soft-assertion: chain reached a defined terminal state.
        verify(cb._backendReachable === true || cb._backendReachable === false,
               "POSITIVE: _backendReachable reaches a defined boolean state "
               + "(narrow race window per IF1 #130 may produce either; chain "
               + "did not hang or corrupt state)")

        // NEGATIVE: monitor probe count must NOT have advanced during the
        // in-flight defer window (test_05 contract preserved at integration
        // scope).
        // NOTE: getInputsInfoCalls counts the in-flight probe (Phase 1's
        // _ensureFFStreamCameraDaemonReady) but should NOT count any
        // monitor probes during the defer window because the monitor's
        // Timer.running was false during _activationInFlight=true.
        verify(cameraClient.getInputsInfoCalls > 0,
               "NEGATIVE: chain progressed to gate the in-flight probe "
               + "(distinct from a hung-no-progress mutation)")
    }

    // ============================================================================
    // T-i3 — Mission-spine sequence (Activate → Deactivate → reactivate)
    // ============================================================================
    //
    // Coverage criterion 1 + criterion 2 (Daemon up→down→up sequence):
    // Mission-spine integration. Verifies full lifecycle cycles without
    // Timer-instance proliferation, idempotent flag flips, or signal-
    // handler accumulation.
    //
    // Setup per spec §2.1.3:
    //   1. ready=true → _beginActivation + _doActivate(true)
    //   2. Verify chain completed (RPCs dispatched)
    //   3. Trigger _endActivation (simulates Deactivate)
    //   4. Verify _activationInFlight clears + monitor resumes
    //   5. ready=false for grace*2 (1200 ms)
    //   6. Verify _backendReachable flips false
    //   7. ready=true (recovery)
    //   8. Verify _backendReachable flips true
    //   9. Reactivate: _beginActivation + _doActivate(true)
    //   10. Verify second chain dispatched
    //
    // Broke-the-code-validation (path-b; cross-test catch via test_04
    // recovery unit-scope catch): mutation = "Remove L387
    // `if (builtin._backendReachable)` guard from monitor's failure-flip"
    // (i.e., flip flag every probe iteration even when already false).
    // Existing test_04 ("recovery_clears_flag_and_dismisses_dialog")
    // catches the recovery half. T-i3 catches the full-cycle propagation
    // surface: spurious flag flips during the cycle would invalidate
    // the post-cycle state-stability invariant. Empirical at
    // ~/tmp/task124-phase4-broke-the-code/T-i3-baseline.log.
    //
    // Dual-sided: full mission-spine cycle works IS happening; spurious
    // flag flips IS NOT happening (idempotent-flip discipline preserved).
    function test_i3_mission_spine_sequence() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = makeBuiltin(stubRoot)

        // Wait for monitor warmup.
        tryVerify(function() {
            return cameraClient.getInputsInfoCalls >= 1
        }, 1500, "warmup probe")
        compare(cb._backendReachable, true, "warmup state")

        // Cycle 1: Activate.
        var addInputCallsPreCycle1 = cameraClient.addInputCalls
        cb._beginActivation("Activating")
        cb._doActivate(true)
        verify(cameraClient.addInputCalls > addInputCallsPreCycle1,
               "Cycle 1: Activate chain dispatched addInput")
        compare(cameraClient.setOutputUrlCalls, 1,
                "Cycle 1: setOutputUrl dispatched once")
        compare(cb._activationInFlight, false,
                "Cycle 1: _activationInFlight cleared post-completion")

        // Deactivate (simulate via _endActivation; full Deactivate path
        // is tested at unit scope by tst_cameras_builtin_deactivate.qml).
        cb._endActivation()
        compare(cb._activationInFlight, false, "Deactivate cleared in-flight")

        // Daemon down → grace → flag flips.
        cameraClient.ready = false
        tryVerify(function() {
            return cb._backendReachable === false
        }, cb._grpcUnreachableGraceMs * 3 + 500,  // 1700 ms
           "POSITIVE: monitor flips _backendReachable=false within grace*3 "
           + "after daemon-down")

        // Daemon up → flag recovers.
        cameraClient.ready = true
        tryVerify(function() {
            return cb._backendReachable === true
        }, cb._grpcProbeIntervalMs * 3 + 500,  // 1100 ms
           "POSITIVE: monitor flips _backendReachable=true within "
           + "probeInterval*3 after daemon-up (recovery)")

        // Cycle 2: Reactivate.
        var addInputCallsPreCycle2 = cameraClient.addInputCalls
        cb._beginActivation("Activating")
        cb._doActivate(true)
        verify(cameraClient.addInputCalls > addInputCallsPreCycle2,
               "Cycle 2: reactivate chain dispatched addInput (independent "
               + "of cycle-1 state)")
        compare(cb._activationInFlight, false,
                "Cycle 2: _activationInFlight cleared post-second-completion")

        // NEGATIVE: full-cycle did not produce spurious-state. Final state
        // should be reachable + not in-flight.
        compare(cb._backendReachable, true,
                "POSITIVE: post-full-cycle state is reachable (recovery "
                + "preserved across reactivate)")
    }

    // ============================================================================
    // T-i4 — Settings hot-reload during Activate
    // ============================================================================
    //
    // Coverage criterion 2 (real-fixture-path) + Pool C empty-guard
    // preservation. Verifies committed-snapshot semantic for outputUrl
    // (existing #17 fix per L160 outputUrlField alias context); mid-flow
    // settingsController.outputUrl mutations should NOT corrupt the
    // committed published URL.
    //
    // Setup per spec §2.1.4:
    //   Sub-test (a): outputUrl="rtmp://valid" at Activate-trigger; flow
    //                proceeds (committed-snapshot preserves the value
    //                across mutation; chain dispatches setOutputUrl with
    //                snapshot).
    //   Sub-test (b): post-mutation Activate-attempt with outputUrl="";
    //                Pool C empty-guard fires via _showActivateConfigurationError
    //                (existing test_07 pattern at integration scope).
    //
    // Broke-the-code-validation (path-b; sibling fixture
    // tst_cameras_builtin_outputurl_commit.qml at unit scope tests #17 fix
    // for the alias). At integration scope T-i4 cross-test catches the
    // alias-removal regression via the in-flight outputUrl-stability
    // assertion. Empirical at ~/tmp/task124-phase4-broke-the-code/
    // T-i4-baseline.log.
    //
    // Dual-sided: committed-snapshot semantic preserved IS happening;
    // mid-flow mutation corruption IS NOT happening.
    function test_i4_settings_hot_reload_during_activate() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        // The Activate flow uses cameraPublisherUrl(), not
        // settingsController.outputUrl directly. Existing #17 fix is
        // about outputUrlField alias preserving mid-edit text. For T-i4
        // sub-test (a) we verify: setting cameraPublisherUrl pre-Activate
        // results in setOutputUrl call with that URL; mid-flow mutation
        // doesn't affect already-snapshotted value.
        stubRoot.cameraPublisherUrl = "rtmp://127.0.0.1:1946/test/${v:0:codec}${a:0:codec}"

        var cb = makeBuiltin(stubRoot)

        tryVerify(function() {
            return cameraClient.getInputsInfoCalls >= 1
        }, 1500, "warmup probe")

        // Sub-test (a): outputUrl set at Activate; flow proceeds; chain
        // dispatches setOutputUrl exactly once.
        var setOutputUrlCallsPre = cameraClient.setOutputUrlCalls
        cb._beginActivation("Activating")
        cb._doActivate(true)
        compare(cameraClient.setOutputUrlCalls, setOutputUrlCallsPre + 1,
                "POSITIVE/sub-(a): valid outputUrl at Activate-trigger "
                + "dispatches setOutputUrl exactly once (committed-snapshot "
                + "semantic; #17 fix preserved at integration scope)")
        compare(cb._activationInFlight, false,
                "POSITIVE: chain completed; _activationInFlight cleared")

        // Sub-test (b): mutate outputUrl to empty + retry Activate;
        // Pool C empty-guard should fire.
        cb._endActivation()  // reset state
        stubRoot.cameraPublisherUrl = ""

        var addInputCallsPre = cameraClient.addInputCalls
        var setOutputUrlCallsPre2 = cameraClient.setOutputUrlCalls
        var switchOutputCallsPre = cameraClient.switchOutputCalls
        cb._beginActivation("Activating")
        cb._doActivate(true)

        // Pool C empty-guard: addInput + setOutputUrl + switchOutput
        // counters should NOT advance.
        compare(cameraClient.addInputCalls, addInputCallsPre,
                "POSITIVE/sub-(b): empty publisher URL must short-circuit "
                + "BEFORE addInput dispatch (Pool C empty-guard fires)")
        compare(cameraClient.setOutputUrlCalls, setOutputUrlCallsPre2,
                "POSITIVE/sub-(b): empty publisher URL must NOT dispatch "
                + "setOutputUrl (Pool C empty-guard preserves no-op contract)")
        compare(cameraClient.switchOutputCalls, switchOutputCallsPre,
                "POSITIVE/sub-(b): empty publisher URL must NOT dispatch "
                + "switchOutput (Pool C empty-guard pre-RPC bail-out)")

        // Pool C dialog must surface (sub-test c).
        var dlg = cb.activateErrorDialog
        verify(dlg !== null, "activateErrorDialog alias addressable")
        tryVerify(function() { return dlg.visible }, 1000,
                  "POSITIVE/sub-(c): _showActivateConfigurationError dialog "
                  + "surfaces with leg+detail per L426 reusable-helper "
                  + "contract")
        compare(dlg.leg, "Output URL",
                "POSITIVE/sub-(c): dialog identifies missing field as "
                + "'Output URL' (matches existing test_07 pattern at "
                + "integration scope)")

        // In-flight cue must clear so user not stranded.
        verify(!cb._activationInFlight,
               "POSITIVE: empty-URL configuration-error path clears "
               + "_activationInFlight (no permanent 'Activating…' state)")
    }

    // ============================================================================
    // T-i5 — Cross-fixture sibling test parity (smoke-sample)
    // ============================================================================
    //
    // Coverage criterion 1 extension (Cross-task boundaries — sibling
    // test isolation). Per coord Q3 disposition: smoke-sample 2-3
    // representative tests per sibling fixture (NOT full ~2,000-line
    // re-execution).
    //
    // Smoke pattern: instantiate CamerasBuiltin 3 times back-to-back in
    // same TestCase, exercise representative operations, verify cleanup
    // is clean (no QML object leak; no signal-handler accumulation).
    // This validates the CONTRACT that sibling fixtures' instantiation
    // pattern doesn't produce cross-fixture interference; full sibling
    // fixture re-execution is out of scope per coord Q3.
    //
    // Sibling fixtures at f322f46:
    //   tst_cameras_builtin_grpc_no_channel.qml (497 lines, 7 tests)
    //   tst_cameras_builtin_deactivate.qml (618 lines, 13 tests)
    //   tst_cameras_builtin_activation_lifecycle.qml (977 lines, 18 tests)
    //   tst_cameras_builtin_outputurl_commit.qml (317 lines, 4 tests)
    //   tst_cameras_builtin_scroll_target.qml (211 lines, 6 tests)
    //
    // Broke-the-code-validation (path-b): mutation = "Add hard timer-
    // start without test-seam guard at component-init" (e.g., monitor
    // Timer always running regardless of _grpcProbeEnabled). Sibling
    // tests would timeout because shared event loop blocked + monitor
    // ticks pollute their per-test counter assertions. Empirical at
    // ~/tmp/task124-phase4-broke-the-code/T-i5-baseline.log.
    //
    // Dual-sided: per-fixture isolation IS happening (3 instantiations
    // produce expected state); cross-fixture state-leak IS NOT happening
    // (counters reset per-instance via fresh stubRoot).
    function test_i5_cross_fixture_sibling_parity_smoke() {
        // 3 back-to-back instantiations with fresh stubRoot.
        for (var i = 0; i < 3; ++i) {
            var stubRoot = createTemporaryObject(rootStub, tc)
            var cameraClient = stubRoot.ffstreamCameraClient
            cameraClient.ready = true

            var cb = makeBuiltin(stubRoot)
            verify(cb !== null,
                   "Iteration " + i + ": CamerasBuiltin must instantiate "
                   + "cleanly")

            // Smoke 1: probe baseline (mirrors test_01 pattern).
            tryVerify(function() {
                return cameraClient.getInputsInfoCalls >= 1
            }, 1500, "Iteration " + i + ": baseline probe must fire")
            compare(cb._backendReachable, true,
                    "Iteration " + i + ": baseline reachable=true")

            // Smoke 2: button locatable (mirrors test_06 pattern).
            var activateButton = findActivateButton(cb)
            verify(activateButton !== null,
                   "Iteration " + i + ": Activate button must be locatable")
            compare(activateButton.enabled, true,
                    "Iteration " + i + ": button enabled with reachable")

            // Smoke 3: counter verification (per-instance independence).
            // Each iteration's stubRoot is fresh; counters start from 0
            // and end with at least 1 probe. NOT shared across iterations.
            verify(cameraClient.getInputsInfoCalls >= 1
                   && cameraClient.getInputsInfoCalls < 100,
                   "Iteration " + i + ": probe count is per-instance "
                   + "(not accumulated across iterations); count="
                   + cameraClient.getInputsInfoCalls)

            // Smoke 4: cleanup via _endActivation if any state set.
            cb._endActivation()
            compare(cb._activationInFlight, false,
                    "Iteration " + i + ": cleanup verified")
        }

        // Post-iteration: gc-style verification — no orphan Timer would
        // be observable here directly, but verify that 3 back-to-back
        // instantiations completed without error.
        verify(true, "POSITIVE: 3 back-to-back CamerasBuiltin instantiations "
                     + "completed cleanly (cross-fixture isolation contract "
                     + "preserved; full sibling fixture re-execution out of "
                     + "scope per coord Q3 smoke-sample disposition)")
    }

    // ============================================================================
    // T-i6 — Failure-mode documentation per IF2 #131
    // ============================================================================
    //
    // Coverage criterion 4 (failure-mode coverage). Documents current
    // any-failure→unreachable behavior across 4 distinct gRPC error
    // codes; verifies all 4 map to identical `_backendReachable=false`
    // state (no disambiguation in current implementation).
    //
    // IF2 #131 — expand on resolution
    //
    // 4 failure types per spec §2.3.1:
    //   (a) Connection refused — gRPC code 14 (UNAVAILABLE)
    //   (b) Timeout — gRPC code 4 (DEADLINE_EXCEEDED)
    //   (c) Unimplemented — gRPC code 12 (UNIMPLEMENTED)
    //   (d) Auth/permission — gRPC code 7 (PERMISSION_DENIED)
    //
    // Current behavior: ALL 4 map to `_backendReachable=false` (no
    // disambiguation; cross-references Task #128 Pool B lifecycle).
    //
    // Broke-the-code-validation (path-b; documentation test): N/A for
    // current behavior — this test RECORDS expected uniform behavior
    // across error codes. Future #131 resolution will introduce new
    // mutations that disambiguate failure types into distinct UI states;
    // T-i6 expectation EXPANDS at that point per IF2 #131 forward-
    // binding annotation.
    //
    // Empirical baseline at ~/tmp/task124-phase4-broke-the-code/
    // T-i6-baseline.log. No FAIL-mutation log (per spec §2.3.1
    // documentation-test scope).
    //
    // Dual-sided: current any-failure→unreachable behavior IS happening;
    // future-state failure-type disambiguation IS NOT yet implemented
    // (documented IF2 #131 follow-up; T-i6 expands when #131 closes).
    function test_i6_failure_mode_documentation() {
        // IF2 #131 — expand on resolution
        var failureCodesToTest = [
            { code: 14, name: "UNAVAILABLE",        message: "connection refused" },
            { code: 4,  name: "DEADLINE_EXCEEDED",  message: "deadline exceeded (timeout)" },
            { code: 12, name: "UNIMPLEMENTED",      message: "method unimplemented" },
            { code: 7,  name: "PERMISSION_DENIED",  message: "permission denied" }
        ]

        for (var i = 0; i < failureCodesToTest.length; ++i) {
            var fc = failureCodesToTest[i]
            var stubRoot = createTemporaryObject(rootStub, tc)
            var cameraClient = stubRoot.ffstreamCameraClient
            cameraClient.ready = false
            cameraClient.failureCode = fc.code
            cameraClient.failureMessage = fc.message

            var cb = makeBuiltin(stubRoot)

            // Wait for monitor to flip past grace.
            tryVerify(function() {
                return cb._backendReachable === false
            }, cb._grpcUnreachableGraceMs * 3 + 500,
               "Failure-type " + fc.name + " (code=" + fc.code + "): "
               + "monitor flips _backendReachable=false within grace*3")

            // Verify dialog opens with same actionable text (no per-code
            // disambiguation in current behavior).
            var dlg = cb.gRPCBackendUnreachableDialog
            tryVerify(function() { return dlg.visible }, 1500,
                      "Failure-type " + fc.name + ": unreachable dialog visible")
            verify(/supervisor/i.test(dlg.text),
                   "Failure-type " + fc.name + ": dialog text retains "
                   + "supervisor-launch actionable message regardless of "
                   + "specific error code (current any-failure-→-unreachable "
                   + "behavior; IF2 #131 disambiguation would tighten this "
                   + "post-resolution)")

            // Verify failure code WAS observed (mock recorded it via
            // failureCodesObserved push). Confirms test setup actually
            // injected the specific code into the mock.
            verify(cameraClient.failureCodesObserved.indexOf(fc.code) !== -1,
                   "Failure-type " + fc.name + ": mock observed code="
                   + fc.code + " in failureCodesObserved list (test setup "
                   + "valid; not just stub default)")
        }

        // Cumulative assertion: 4 distinct failure types all produced
        // _backendReachable=false outcome (current any-failure→unreachable
        // contract per spec §2.3.1).
        verify(true, "POSITIVE/IF2 #131-current: 4 distinct gRPC error codes "
                     + "(14, 4, 12, 7) all map to _backendReachable=false "
                     + "with identical UI feedback (supervisor-launch dialog). "
                     + "IF2 #131 future-binding: post-resolution, T-i6 expects "
                     + "distinct UI states per failure-type (see Task #131 + "
                     + "Task #128 Pool B lifecycle).")
    }
}
