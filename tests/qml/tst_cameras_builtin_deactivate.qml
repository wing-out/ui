import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests for CamerasBuiltin.qml Deactivate daemon-stop behavior.
///
/// Falsifier intent: Deactivate must send the dedicated ffstream-camera
/// daemon a clean End RPC. It must not tear down by removing priority-0
/// inputs; RemoveInput remains only for Activate rollback / Re-Activate
/// purge paths.
///
/// Strategy: instantiate CamerasBuiltin with a stub root that exposes
/// minimal mocks for streamingSettings / ffstreamClient / microphoneController
/// (so QML bindings resolve without a live gRPC channel). Dialog tests call
/// _showDeactivateError(detail) directly; lifecycle tests drive _doDeactivate.
TestCase {
    id: tc
    name: "CamerasBuiltinDeactivate"
    when: windowShown
    width: 540
    height: 960

    // Minimal stub for builtin.root — provides the four properties
    // referenced by CamerasBuiltin.qml during component instantiation
    // (settingsController, ffstreamClient, microphoneController,
    // grpcCallOptions).
    Component {
        id: rootStub
        QtObject {
            id: rootObject
            // grpcCallOptions stub — Activate / Deactivate paths now
            // thread builtin.root.grpcCallOptions into every RPC site
            // (B1 SSOT fix). Provided here for shape-equivalence with
            // Main.qml's GrpcCallOptions; the call sites are NOT
            // exercised by this test (we call _showDeactivateError
            // directly), but the property is referenced by lazily-
            // evaluated function bodies that the QML engine may scan.
            property QtObject grpcCallOptions: QtObject {
                property int deadlineTimeout: 10000
            }
            property QtObject ffstreamCameraStartupProbeGrpcCallOptions: QtObject {
                property int deadlineTimeout: 400
            }
            property string ffstreamCameraHost: "http://127.0.0.1:3594"
            function builtinCameraPublisherUrl() {
                return "rtmp://127.0.0.1:1946/test/${v:0:codec}${a:0:codec}"
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
                property string videoCodec: "h265_mediacodec"
                property string audioCodec: "aac"
                property int audioSampleRate: 48000
                property int audioBitrateKbps: 64
                property int audioChannels: 1
                property string outputUrl: ""
                property string preferredCamera: "Front"
                property int preferredMicrophoneId: 0
                property int userIntentEpoch: 0
                property int activeCameraNum: 42
                property int activeMicrophoneNum: 43
                property int deactivateCalls: 0
                function bumpUserIntentEpoch() {}
                function activate() {}
                function deactivate() {
                    deactivateCalls += 1
                    active = false
                }
            }
            // ffstreamClient stub: only needs to exist so the QML bindings
            // referencing builtin.root.ffstreamClient resolve. The Deactivate
            // path is not exercised; we call _showDeactivateError directly.
            property QtObject ffstreamClient: QtObject {
                function processGRPCError(_) {}
                function getInputsInfo(_, _, _) {}
                function removeInput(_, _, _, _, _) {}
            }
            // ffstreamCameraClient stub (#350): CamerasBuiltin's Activate /
            // Deactivate paths target this client, not ffstreamClient. The
            // _showDeactivateError test path doesn't actually dispatch
            // RPCs — it calls the dialog opener directly — but the QML
            // bindings reference builtin.root.ffstreamCameraClient at
            // component-load time and would surface a TypeError without it.
            property QtObject ffstreamCameraClient: QtObject {
                property bool ready: true
                property int endCalls: 0
                property int removeInputCalls: 0
                property int processGrpcErrorCalls: 0
                property int getInputsInfoCalls: 0
                property int addInputCalls: 0
                property int setOutputUrlCalls: 0
                property int switchOutputCalls: 0
                property var addInputObservedVideoCodecs: []
                property var switchOutputCodecs: []
                property bool endShouldFail: false
                property var endError: ({ code: 14, message: "daemon unavailable" })
                property var probeResults: []
                property var probeOptionDeadlines: []
                function isChannelReady() { return ready }
                function setServerUri(_) {}
                function processGRPCError(_) { processGrpcErrorCalls += 1 }
                function getInputsInfo(finishCallback, errorCallback, _options) {
                    getInputsInfoCalls += 1
                    probeOptionDeadlines.push(_options && _options.deadlineTimeout !== undefined
                                              ? _options.deadlineTimeout : -1)
                    rootObject.callOrder.push("probe")
                    if (probeResults.length > 0) {
                        var result = probeResults.shift()
                        if (result === false) {
                            errorCallback({ code: 14, message: "daemon unavailable" })
                            return
                        }
                        if (result && result.error) {
                            errorCallback(result.error)
                            return
                        }
                        if (result === true) {
                            finishCallback({ inputs: [] })
                            return
                        }
                        finishCallback(result)
                        return
                    }
                    if (ready) {
                        finishCallback({ inputs: [] })
                        return
                    }
                    errorCallback({ code: 14, message: "daemon unavailable" })
                }
                function removeInput(_, _, _, _, _) { removeInputCalls += 1 }
                function addInput(_priority, _url, _customOptions, finishCallback, _errorCallback, _options) {
                    addInputCalls += 1
                    addInputObservedVideoCodecs.push(rootObject.streamingSettings.videoCodec)
                    rootObject.callOrder.push("addInput")
                    finishCallback({ num: addInputCalls - 1 })
                }
                function setOutputUrl(_url, finishCallback, _errorCallback, _options) {
                    setOutputUrlCalls += 1
                    rootObject.callOrder.push("setOutputUrl")
                    finishCallback({})
                }
                function switchOutput(
                    _videoCodec, _width, _height, _videoBitrate,
                    _audioCodec, _audioSampleRate, _audioBitrate,
                    _maxBitrate, finishCallback, _errorCallback, _options) {
                    switchOutputCalls += 1
                    switchOutputCodecs.push(_videoCodec)
                    rootObject.callOrder.push("switchOutput")
                    finishCallback({})
                }
                function end(finishCallback, errorCallback, _options) {
                    endCalls += 1
                    if (endShouldFail) {
                        errorCallback(endError)
                        return
                    }
                    finishCallback({})
                }
            }
            // microphoneController stub: the mic ComboBox model binding reads
            // .devices on it; nil is acceptable but we provide an empty list
            // for cleanliness.
            property QtObject microphoneController: QtObject {
                property var devices: []
            }
        }
    }

    Component {
        id: camerasBuiltinComponent
        CamerasBuiltin {
            // Opt out of the Task #124 proactive gRPC reachability monitor
            // for this test file. The monitor's continuous getInputsInfo
            // ticker would inflate cameraClient.getInputsInfoCalls counts
            // (test_04 etc.) and consume probeResults entries queued for
            // the user-intent-bound Deactivate flow. Tests that exercise
            // the proactive monitor live in
            // tst_cameras_builtin_grpc_no_channel.qml.
            _grpcProbeEnabled: false
        }
    }

    function builtinInputsReply() {
        return {
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
        }
    }

    function test_01_deactivate_error_detail_opens_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        verify(stubRoot !== null, "rootStub must instantiate")

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate with stub root")

        // Sanity: dialog is NOT open before we call the helper.
        var dlg = cb.deactivateErrorDialog || null
        verify(dlg !== null, "deactivateErrorDialog must be addressable by id "
               + "(or via property exposure)")
        verify(!dlg.visible, "deactivateErrorDialog must start closed")

        cb._showDeactivateError("gRPC code 2: failed")
        // open() may transition asynchronously on some Qt platforms; poll.
        tryVerify(function() { return dlg.visible }, 1000,
                  "deactivateErrorDialog.visible must become true after "
                  + "_showDeactivateError(detail)")
        compare(dlg.detail, "gRPC code 2: failed",
                "detail property must reflect the argument")
    }

    function test_02_empty_deactivate_error_does_not_open_dialog() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null)

        var dlg = cb.deactivateErrorDialog || null
        verify(dlg !== null)
        verify(!dlg.visible, "must start closed")

        cb._showDeactivateError("")
        // Give Qt a chance to process any pending events that would have
        // opened the dialog if the guard were broken.
        wait(100)
        verify(!dlg.visible,
               "deactivateErrorDialog must NOT open for an empty detail")
    }

    function test_03_dialog_text_includes_detail() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null)

        var dlg = cb.deactivateErrorDialog || null
        verify(dlg !== null)

        cb._showDeactivateError("gRPC code 13: internal")
        tryVerify(function() { return dlg.visible }, 1000)
        verify(dlg.text.indexOf("gRPC code 13: internal") !== -1,
               "dialog.text must include the failure detail; "
               + "got: \"" + dlg.text + "\"")
    }

    // test_04: Deactivate's primary teardown is End RPC, but End accepted
    // is not enough. The UI may commit inactive only after a follow-up probe
    // observes the built-in camera/mic inputs gone, or observes the daemon
    // unavailable. A supervisor-relaunched daemon is acceptable if it is idle.
    function test_04_deactivate_waits_for_idle_after_end_without_removeInput() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.active = true
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.probeResults = [builtinInputsReply(), { inputsData: [] }]

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeIntervalMs = 10
        verify(typeof cb._doDeactivate === "function",
               "_doDeactivate must be a top-level helper so the test can "
               + "drive the production Deactivate path")

        cb._doDeactivate()

        compare(cameraClient.endCalls, 1,
                "Deactivate must send exactly one End RPC to ffstream-camera")
        compare(cameraClient.removeInputCalls, 0,
                "Deactivate must not use RemoveInput as primary teardown")
        compare(settings.deactivateCalls, 0,
                "End reply alone must not commit inactive while the daemon "
                + "still reports built-in camera/mic inputs")

        tryVerify(function() { return settings.deactivateCalls === 1 }, 1500,
                  "Deactivate must commit inactive once a post-End probe "
                  + "observes no built-in camera/mic inputs")
        compare(cameraClient.getInputsInfoCalls, 2,
                "Deactivate must keep probing until built-in inputs are gone")
        compare(settings.deactivateCalls, 1,
                "idle daemon after End must commit inactive UI state")
        compare(settings.activeCameraNum, -1,
                "Deactivate must clear tracked camera input num")
        compare(settings.activeMicrophoneNum, -1,
                "Deactivate must clear tracked microphone input num")
        verify(!cb._activationInFlight,
               "Deactivate completion must clear the in-flight cue")
    }

    function test_05_deactivate_end_error_keeps_active_and_retryable() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.active = true
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.endShouldFail = true

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        cb._doDeactivate()

        compare(cameraClient.endCalls, 1,
                "Deactivate must attempt End exactly once per tap")
        compare(cameraClient.processGrpcErrorCalls, 1,
                "Deactivate End errors must still feed the reconnect/error path")
        compare(settings.deactivateCalls, 0,
                "failed End must not commit inactive state")
        verify(settings.active,
               "failed End must leave the UI active so Deactivate can be retried")
        compare(settings.activeCameraNum, 42,
                "failed End must not clear tracked camera input num")
        compare(settings.activeMicrophoneNum, 43,
                "failed End must not clear tracked microphone input num")
        verify(!cb._activationInFlight,
               "failed End must clear the in-flight cue so retry is enabled")

        var dlg = cb.deactivateErrorDialog || null
        verify(dlg !== null)
        tryVerify(function() { return dlg.visible }, 1000,
                  "failed End must surface a user-visible retryable error")
        verify(dlg.text.indexOf("daemon unavailable") !== -1,
               "dialog text must include the End failure detail; got: \""
               + dlg.text + "\"")

        cb._doDeactivate()
        compare(cameraClient.endCalls, 2,
                "remaining active after a failed End must allow retry")
    }

    function test_06_activate_does_not_start_supervisor_when_daemon_ready() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        cb._beginActivation("Activating")
        cb._doActivate()

        compare(stubRoot.startFFStreamCameraDaemonCalls, 0,
                "Activate must not spawn a duplicate supervisor when "
                + "the daemon already responds")
        compare(cameraClient.getInputsInfoCalls, 1,
                "Activate must probe daemon reachability before AddInput")
        compare(cameraClient.addInputCalls, 2,
                "Activate must add camera and microphone after readiness")
        compare(stubRoot.callOrder[0], "probe",
                "first side effect must be daemon reachability probe")
        compare(stubRoot.callOrder[1], "addInput",
                "AddInput must follow the successful readiness probe")
    }

    function verifyActivateOverridesPersistedCodec(staleCodec) {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.videoCodec = staleCodec
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")

        cb._beginActivation("Activating")
        cb._doActivate()

        compare(cameraClient.addInputCalls, 2,
                "Activate must add camera and microphone after readiness")
        compare(cameraClient.switchOutputCalls, 1,
                "Activate must configure camera daemon output exactly once")
        compare(settings.videoCodec, settings.missionVideoCodec,
                "Activate must reset stale persisted camera videoCodec to AV1")
        compare(cameraClient.addInputObservedVideoCodecs[0], settings.missionVideoCodec,
                "camera AddInput must not observe stale persisted " + staleCodec)
        compare(cameraClient.addInputObservedVideoCodecs[1], settings.missionVideoCodec,
                "microphone AddInput must not observe stale persisted " + staleCodec)
        compare(cameraClient.switchOutputCodecs[0], settings.missionVideoCodec,
                "SwitchOutput must use mission AV1 codec")
        verify(cameraClient.switchOutputCodecs[0] !== staleCodec,
               "SwitchOutput must not send stale persisted " + staleCodec)
        verify(!cb._activationInFlight,
               "successful activation chain must clear the in-flight cue")
    }

    function test_07_activate_overrides_persisted_h265_before_camera_daemon_calls() {
        verifyActivateOverridesPersistedCodec("h265_mediacodec")
    }

    function test_08_activate_overrides_persisted_h264_before_camera_daemon_calls() {
        verifyActivateOverridesPersistedCodec("h264_mediacodec")
    }

    function test_09_activate_waits_for_rc_local_daemon_without_app_start() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false
        cameraClient.probeResults = [false, true]

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeAttempts = 3
        cb.ffstreamCameraStartupProbeIntervalMs = 10

        cb._beginActivation("Activating")
        cb._doActivate()

        tryVerify(function() { return cameraClient.addInputCalls === 2 },
                  1500,
                  "Activate must wait for the rc.local-started daemon to "
                  + "become reachable before AddInput")
        compare(stubRoot.startFFStreamCameraDaemonCalls, 0,
                "Activate must not start Ubuntu, su/chroot, or the "
                + "ffstream-camera loop script from Wingout")
        compare(cameraClient.getInputsInfoCalls, 2,
                "Activate must probe, then retry readiness without "
                + "launching the supervisor from the app")
        compare(cameraClient.addInputCalls, 2,
                "Activate must add camera and microphone after readiness")
        compare(stubRoot.callOrder[0], "probe",
                "first side effect must be reachability probe")
        compare(stubRoot.callOrder[1], "probe",
                "second side effect must be another readiness probe")
        compare(stubRoot.callOrder[2], "addInput",
                "AddInput must not run before daemon readiness")
        compare(settings.deactivateCalls, 0)
        verify(!cb._activationInFlight,
               "successful activation chain must clear the in-flight cue")
    }

    function test_10_activate_without_rc_local_daemon_is_visible_and_recoverable() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false
        cameraClient.probeResults = [false]

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeAttempts = 1
        cb.ffstreamCameraStartupProbeIntervalMs = 10

        cb._beginActivation("Activating")
        cb._doActivate()

        tryVerify(function() { return cb.cameraDaemonStoppedDialog.visible },
                  1500,
                  "missing rc.local-started daemon must be user-visible")
        compare(stubRoot.startFFStreamCameraDaemonCalls, 0,
                "Activate must not use an app-side restart hook")
        compare(cameraClient.addInputCalls, 0,
                "Activate must not issue AddInput when the stopped daemon "
                + "is not reachable")
        verify(!cb._activationInFlight,
               "stopped-daemon failure must re-enable Activate for retry")
    }

    function test_11_activate_after_clean_deactivate_accepts_idle_relaunched_daemon() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.active = true
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true
        cameraClient.probeResults = []

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeIntervalMs = 10

        cb._doDeactivate()
        compare(cameraClient.endCalls, 1,
                "Deactivate must issue the clean End RPC")
        verify(!settings.active,
               "clean Deactivate must commit inactive UI state")
        verify(cb._ffstreamCameraDaemonKnownStopped,
               "clean Deactivate must mark the camera daemon known-stopped "
               + "so the next Activate cannot accept the old listener")

        stubRoot.callOrder = []
        stubRoot.startFFStreamCameraDaemonCalls = 0
        cameraClient.getInputsInfoCalls = 0
        cameraClient.addInputCalls = 0
        cameraClient.setOutputUrlCalls = 0
        cameraClient.switchOutputCalls = 0
        cameraClient.probeResults = [true]

        cb._beginActivation("Activating")
        cb._doActivate()

        tryVerify(function() { return cameraClient.addInputCalls === 2 },
                  1500,
                  "Activate after clean Deactivate must work when the "
                  + "supervisor has already relaunched an idle daemon")

        compare(stubRoot.startFFStreamCameraDaemonCalls, 0,
                "known-stopped Activate must still avoid app-side "
                + "supervisor startup")
        compare(cameraClient.getInputsInfoCalls, 1,
                "known-stopped Activate may accept an already-relaunched "
                + "idle daemon as ready")
        compare(stubRoot.callOrder[0], "probe",
                "known-stopped Activate must probe daemon readiness")
        compare(stubRoot.callOrder[1], "addInput",
                "AddInput must follow idle daemon readiness")
        verify(!cb._ffstreamCameraDaemonKnownStopped,
               "successful restart readiness must clear known-stopped state")
        verify(!cb._activationInFlight,
               "successful activation chain must clear the in-flight cue")
    }

    function test_12_startup_probes_use_short_call_options() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = false
        cameraClient.probeResults = [false, true]

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeAttempts = 3
        cb.ffstreamCameraStartupProbeIntervalMs = 10

        cb._beginActivation("Activating")
        cb._doActivate()

        tryVerify(function() { return cameraClient.addInputCalls === 2 },
                  1500)
        compare(cameraClient.probeOptionDeadlines.length, 2,
                "stopped-daemon Activate must perform initial and startup probes")
        for (var i = 0; i < cameraClient.probeOptionDeadlines.length; ++i) {
            compare(cameraClient.probeOptionDeadlines[i],
                    stubRoot.ffstreamCameraStartupProbeGrpcCallOptions.deadlineTimeout,
                    "camera startup probe " + i
                    + " must use the short readiness-probe deadline, not "
                    + "the general 10s gRPC deadline")
        }
    }

    function test_13_known_stopped_retries_start_while_new_daemon_unavailable() {
        var stubRoot = createTemporaryObject(rootStub, tc)
        var settings = stubRoot.streamingSettings
        settings.active = true
        var cameraClient = stubRoot.ffstreamCameraClient
        cameraClient.ready = true

        var cb = createTemporaryObject(camerasBuiltinComponent, tc,
                                       { "root": stubRoot })
        verify(cb !== null, "CamerasBuiltin must instantiate")
        cb.ffstreamCameraStartupProbeIntervalMs = 10

        cb._doDeactivate()
        verify(cb._ffstreamCameraDaemonKnownStopped,
               "clean Deactivate must mark the camera daemon known-stopped")

        stubRoot.callOrder = []
        stubRoot.startFFStreamCameraDaemonCalls = 0
        cameraClient.getInputsInfoCalls = 0
        cameraClient.addInputCalls = 0
        cameraClient.ready = false
        cameraClient.probeResults = [false, true]

        cb._beginActivation("Activating")
        cb._doActivate()

        tryVerify(function() { return cameraClient.addInputCalls === 2 },
                  1500,
                  "known-stopped Activate must keep probing until the "
                  + "rc.local-supervised daemon is reachable")

        compare(stubRoot.startFFStreamCameraDaemonCalls, 0,
                "known-stopped Activate must not request supervisor start "
                + "from the app")
        compare(stubRoot.callOrder[0], "probe",
                "first known-stopped probe must check daemon readiness")
        compare(stubRoot.callOrder[1], "probe",
                "second probe may observe the supervised daemon")
        compare(stubRoot.callOrder[2], "addInput",
                "AddInput must follow supervised daemon readiness")
    }
}
