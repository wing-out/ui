/* This file implements the main UI content for WingOut. */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtGrpc

import streamd 1.0 as StreamD
import ffstream_grpc 1.0 as FFStream
import Platform 1.0
import StreamingSettingsController
import MicrophoneController

Pane {
    id: main
    objectName: "main"
    anchors.fill: parent
    padding: 0

    property var applicationWindow: Window.window
    required property var platformInstance
    property var appSettings
    readonly property string dxProducerHost: appSettings ? appSettings.dxProducerHost : ""

    property bool locked: false
    readonly property bool isLandscape: width > height

    // Retrieve safe area insets from the platform when available.
    property var safeAreaInsets: (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }
    onWidthChanged: safeAreaInsets = (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }
    onHeightChanged: safeAreaInsets = (typeof platform !== 'undefined' && typeof platform["getSafeAreaInsets"] === 'function') ? platform["getSafeAreaInsets"]() : {
        top: 0,
        bottom: 0,
        left: 0,
        right: 0
    }

    readonly property real safeAreaTop: ((safeAreaInsets && safeAreaInsets.top) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaBottom: ((safeAreaInsets && safeAreaInsets.bottom) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaLeft: ((safeAreaInsets && safeAreaInsets.left) || 0) / Screen.devicePixelRatio
    readonly property real safeAreaRight: ((safeAreaInsets && safeAreaInsets.right) || 0) / Screen.devicePixelRatio

    topPadding: 0   // Android already insets the window below status bar; do not double-inset
    leftPadding: safeAreaLeft
    rightPadding: safeAreaRight
    bottomPadding: 0   // Android already insets the window above navigation bar; do not double-inset

    ListModel {
        id: globalChatMessagesModel
    }

    // Use proper QML GrpcCallOptions objects instead of plain JS
    // objects: Qt 6.9 gRPC methods expect QQmlGrpcCallOptions* and
    // cannot convert from a V4ReferenceObject (JS {}).
    GrpcCallOptions {
        id: grpcCallOptions
        deadlineTimeout: 10000
    }
    readonly property int ffstreamCameraStartupProbeDeadlineMs: 400
    readonly property int ffstreamCameraStartupProbeAttempts: 20
    readonly property int ffstreamCameraStartupProbeIntervalMs: 500
    readonly property int ffstreamCameraStartupProbeBudgetMs:
        ffstreamCameraStartupProbeAttempts
        * (ffstreamCameraStartupProbeDeadlineMs
           + ffstreamCameraStartupProbeIntervalMs)
    GrpcCallOptions {
        id: ffstreamCameraStartupProbeGrpcCallOptions
        deadlineTimeout: main.ffstreamCameraStartupProbeDeadlineMs
    }
    GrpcCallOptions {
        id: streamingGrpcCallOptions
        deadlineTimeout: 365 * 24 * 3600 * 1000
    }

    property alias ffstreamClient: ffstreamClient
    property alias ffstreamCameraClient: ffstreamCameraClient
    property alias dxProducerClient: dxProducerClient
    property alias globalChatMessagesModel: globalChatMessagesModel
    property alias grpcCallOptions: grpcCallOptions
    property alias ffstreamCameraStartupProbeGrpcCallOptions: ffstreamCameraStartupProbeGrpcCallOptions
    property alias streamingGrpcCallOptions: streamingGrpcCallOptions
    property alias streamingSettings: streamingSettings
    property alias microphoneController: micCtrl
    readonly property var platform: platformInstance

    MicrophoneController {
        id: micCtrl
    }

    function normalizeGrpcUri(rawValue, defaultScheme) {
        if (rawValue === undefined || rawValue === null) {
            return "";
        }
        var value = String(rawValue).trim();
        if (value.length === 0) {
            return "";
        }
        if (value.startsWith("tcp+ssl://")) {
            value = "https://" + value.substring("tcp+ssl://".length);
        } else if (value.startsWith("tcp+ssl:")) {
            value = "https://" + value.substring("tcp+ssl:".length);
        } else if (value.startsWith("tcp+insecure://")) {
            value = "http://" + value.substring("tcp+insecure://".length);
        } else if (value.startsWith("tcp+insecure:")) {
            value = "http://" + value.substring("tcp+insecure:".length);
        } else if (value.startsWith("tcp://")) {
            value = "http://" + value.substring("tcp://".length);
        } else if (value.startsWith("tcp:")) {
            value = "http://" + value.substring("tcp:".length);
        }
        if (!value.startsWith("http://") && !value.startsWith("https://")) {
            var scheme = defaultScheme && defaultScheme.length > 0 ? defaultScheme : "https";
            value = scheme + "://" + value;
        }
        return value;
    }

    readonly property string normalizedDxProducerHost: normalizeGrpcUri(appSettings ? appSettings.dxProducerHost : "", "https")
    // ffstreamHost must be configured explicitly. No host-derivation fallback —
    // we previously derived a URL from dxProducerHost when ffstreamHost was
    // empty, but that silently overrode the user's value during the brief
    // window when Core.Settings had not yet loaded persisted state, leaving
    // the ffstream client bound to the wrong host indefinitely.
    readonly property string normalizedFFStreamHost: normalizeGrpcUri(
        appSettings ? appSettings.ffstreamHost : "", "https")

    // ffstream-camera runs on the device itself listening at 127.0.0.1:3594.
    // rc.local owns the supervisor/loop-script startup; Wingout only configures
    // the already-supervised daemon at user-tap Activate time.
    readonly property string ffstreamCameraHost: "http://127.0.0.1:3594"

    function startFFStreamCameraDaemon() {
        // Placeholder for a future non-root, app-owned launcher. Current
        // deployments keep daemon startup outside Wingout: rc.local owns the
        // ffstream-camera loop, and this app only configures the running daemon.
        return false
    }

    FFStream.Client {
        id: ffstreamClient
        Component.onCompleted: {
            if (main.normalizedFFStreamHost && main.normalizedFFStreamHost.length > 0) {
                ffstreamClient.setServerUri(main.normalizedFFStreamHost);
                console.log("ffstreamClient setServerUri:", main.normalizedFFStreamHost);
            }
        }
    }

    // Second FFStream client targeting the on-device camera daemon.
    // Drives the built-in camera Activate/Deactivate flow in CamerasBuiltin
    // and owns its own reconcile path (see reconcileWithFFStreamCamera below). The
    // existing ffstreamClient (port 3593) is kept for the streaming-side
    // gRPC surface and is untouched by this addition.
    FFStream.Client {
        id: ffstreamCameraClient
        Component.onCompleted: {
            ffstreamCameraClient.setServerUri(main.ffstreamCameraHost);
            console.log("ffstreamCameraClient setServerUri:", main.ffstreamCameraHost);
        }
    }

    // Persisted codec/output settings (Codec-B). Kept in Main so the
    // auto-AV1-on-connect handler below and the Settings UI both read/write
    // the same instance.
    StreamingSettingsController {
        id: streamingSettings
        onSaveFailed: function(filePath, errorString) {
            console.warn("Main.qml: streamingSettings save failed:", filePath, errorString);
        }
    }

    function enforceRequiredVideoCodec() {
        if (!streamingSettings) return ""
        if (streamingSettings
                && streamingSettings.videoCodec !== streamingSettings.requiredVideoCodec) {
            console.warn("Main.qml: resetting videoCodec from",
                         streamingSettings.videoCodec,
                         "to", streamingSettings.requiredVideoCodec);
            streamingSettings.videoCodec = streamingSettings.requiredVideoCodec;
        }
        return streamingSettings.requiredVideoCodec;
    }

    // Auto-call switchOutput once the mediamtx-side gRPC channel is
    // (re)attached so the required AV1 codec becomes active independent
    // of ffstream's boot-time CLI codec or stale persisted settings.
    //
    // This reconciler never owns the built-in camera Active/Deactivate state.
    // The dedicated ffstream-camera client below is the only source of truth
    // for priority-0 android_camera/android_microphone liveness. The
    // mediamtx-side client may still inspect its own inputs for its legacy
    // auto-apply gate, but a no-built-in-inputs reply must not disable
    // Deactivate while ffstream-camera is live.
    //
    // Retry contract: on RPC failure we schedule a bounded exponential
    // backoff via reconcileRetryTimer (2s -> 4s -> 8s -> 30s cap). A
    // subsequent onChannelChanged resets the delay and starts fresh.
    // Without this, a single transient failure on first connect leaves
    // m_active at boot-default false forever and the UI shows "Activate"
    // even when ffstream actually has the inputs registered.

    property int reconcileRetryDelayMs: 2000
    readonly property int reconcileRetryMaxMs: 30000

    // Channel-bounce epoch: bumped on every onChannelChanged (regardless of
    // ready/not-ready). Captured before each reconcile RPC dispatch; the
    // failure handler bails out (no backoff schedule) if the captured epoch
    // no longer matches — onChannelChanged has already scheduled a fresh
    // reconcile attempt and the stale failure must not pile on a
    // 2-30s-later retry. Mirrors the userIntentEpoch pattern in
    // StreamingSettingsController.
    property int reconcileChannelEpoch: 0

    // Per-client retry state for the camera daemon. Kept separate
    // from reconcileRetryDelayMs / reconcileChannelEpoch above because the
    // streaming client (3593) and the camera client (3594) bounce
    // independently — sharing a single epoch/backoff would let one
    // client's transient failure delay the other client's retry, and
    // a channel-bounce on one would falsely invalidate an in-flight
    // reconcile reply on the other.
    property int reconcileCameraRetryDelayMs: 2000
    property int reconcileCameraChannelEpoch: 0

    Timer {
        id: reconcileRetryTimer
        repeat: false
        // interval is set right before each start() — no fixed value.
        onTriggered: {
            if (!ffstreamClient.isChannelReady()) {
                // Channel went away while we were backing off; abandon —
                // a fresh onChannelChanged will re-arm us if/when it returns.
                return;
            }
            main.reconcileWithFFStream(ffstreamClient);
        }
    }

    Timer {
        id: reconcileCameraRetryTimer
        repeat: false
        onTriggered: {
            if (!ffstreamCameraClient.isChannelReady()) {
                return;
            }
            main.reconcileWithFFStreamCamera(ffstreamCameraClient);
        }
    }

    function reconcileWithFFStream(ffstreamClient) {
        if (!ffstreamClient.isChannelReady()) {
            return;
        }
        // Capture channel epoch as well: if the gRPC channel bounces
        // mid-RPC, the in-flight reply errors out and the failure handler
        // would otherwise schedule an unnecessary backoff retry — but
        // onChannelChanged has already fired a fresh reconcile. Compare
        // captured vs. current epoch in the failure handler to drop the
        // stale failure cleanly.
        var capturedChannelEpoch = main.reconcileChannelEpoch;
        // Invariant: success-path bails on user-intent-epoch mismatch only (the
        // reply data is still valid even if the channel bounced); failure-path
        // bails on channel-epoch mismatch only (a fresh reconcile is already
        // armed by onChannelChanged, no need for a stale-failure retry). Adding
        // a third epoch (e.g. for settings changes) would require deciding which
        // of these two paths it should gate.
        ffstreamClient.getInputsInfo(
            function(reply) {
                var inputs = reply.inputsData || reply.inputs || []
                var hasCam = false, hasMic = false
                for (var i = 0; i < inputs.length; ++i) {
                    var inp = inputs[i]
                    if ((inp.priority || 0) !== 0) continue
                    var opts = (inp.inputConfig && (inp.inputConfig.customOptionsData || inp.inputConfig.customOptions))
                               ? (inp.inputConfig.customOptionsData || inp.inputConfig.customOptions) : []
                    for (var j = 0; j < opts.length; ++j) {
                        if (opts[j].key !== "f") continue
                        if (opts[j].value === "android_camera") hasCam = true
                        else if (opts[j].value === "android_microphone") hasMic = true
                    }
                }
                // Reset the retry backoff on every success.
                main.reconcileRetryDelayMs = 2000;
                if (!(hasCam && hasMic)) {
                    console.log("Main.qml: reconcile says inactive — skipping auto-apply switchOutput");
                    return;
                }
                var requiredVideoCodec = main.enforceRequiredVideoCodec();
                console.log("Main.qml: ffstreamClient channel ready, applying codec",
                    requiredVideoCodec,
                    streamingSettings.width + "x" + streamingSettings.height,
                    streamingSettings.bitrateKbps + "kbps",
                    streamingSettings.audioCodec,
                    streamingSettings.audioSampleRate + "Hz",
                    streamingSettings.audioBitrateKbps + "kbps",
                    "max=" + streamingSettings.maxBitrateKbps + "kbps");
                // Push the persisted output URL before switchOutput; the next
                // SwitchOutputByProps reads URLTemplate when constructing NewSender.
                if (streamingSettings.outputUrl && streamingSettings.outputUrl.length > 0) {
                    ffstreamClient.setOutputUrl(
                        streamingSettings.outputUrl,
                        function(reply2) {
                            console.log("Main.qml: auto setOutputUrl ok");
                        },
                        function(error) {
                            console.warn("Main.qml: auto setOutputUrl failed:", JSON.stringify(error));
                        },
                        main.grpcCallOptions);
                }
                ffstreamClient.switchOutput(
                    requiredVideoCodec,
                    streamingSettings.width,
                    streamingSettings.height,
                    streamingSettings.bitrateKbps * 1000,
                    streamingSettings.audioCodec,
                    streamingSettings.audioSampleRate,
                    streamingSettings.audioBitrateKbps * streamingSettings.audioChannels * 1000,
                    streamingSettings.maxBitrateKbps * 1000,
                    function(reply2) {
                        console.log("Main.qml: auto switchOutput ok");
                    },
                    function(error) {
                        console.warn("Main.qml: auto switchOutput failed");
                        main.processFFStreamGRPCError(ffstreamClient, error);
                    },
                    main.grpcCallOptions);
            },
            function(error) {
                console.warn("Main.qml: reconcile getInputsInfo failed:",
                             JSON.stringify(error))
                main.processFFStreamGRPCError(ffstreamClient, error)
                // Drop the failure if the channel has bounced since dispatch
                // — onChannelChanged already scheduled a fresh reconcile
                // attempt, so piling on a 2-30s backoff retry is noise.
                if (capturedChannelEpoch !== main.reconcileChannelEpoch) {
                    console.log("Main.qml: reconcile failure dropped — channel epoch advanced",
                                capturedChannelEpoch, "->", main.reconcileChannelEpoch);
                    return;
                }
                // Explicit error: do NOT call setActiveFromReconciliation(false)
                // — that would itself be a lie (we don't know the truth).
                // Schedule a bounded exponential backoff retry. Channel-loss
                // is checked by the timer's onTriggered before re-issuing.
                if (!ffstreamClient.isChannelReady()) {
                    return;
                }
                reconcileRetryTimer.interval = main.reconcileRetryDelayMs;
                main.reconcileRetryDelayMs =
                    Math.min(main.reconcileRetryDelayMs * 2, main.reconcileRetryMaxMs);
                console.log("Main.qml: reconcile retry scheduled in",
                            reconcileRetryTimer.interval, "ms (next delay",
                            main.reconcileRetryDelayMs, "ms)");
                reconcileRetryTimer.restart();
            },
            main.grpcCallOptions);
    }

    // Manual mediamtx-side check: restart wingout with the streaming daemon
    // reachable and any legacy priority-0 android inputs already present. This
    // path may auto-apply output settings to that daemon, but it must not flip
    // the shared camera active state. Built-in camera Active/Deactivate state is
    // reconciled only by reconcileWithFFStreamCamera().

    Connections {
        target: ffstreamClient
        function onChannelChanged() {
            // Bump on EVERY channel-changed event (ready OR not-ready) so
            // that any in-flight reconcile RPC sees a stale captured epoch
            // in its failure handler and bails out instead of scheduling a
            // duplicate backoff retry.
            main.reconcileChannelEpoch++;
            if (!ffstreamClient.isChannelReady()) {
                console.log("Main.qml: ffstreamClient channelChanged but channel not ready yet");
                // A previous channel may have left a backoff timer armed; cancel it.
                reconcileRetryTimer.stop();
                return;
            }
            // Fresh channel-ready event resets the retry budget.
            main.reconcileRetryDelayMs = 2000;
            reconcileRetryTimer.stop();
            main.reconcileWithFFStream(ffstreamClient);
        }
    }

    // reconcileWithFFStreamCamera drives the camera-daemon active-state
    // setActiveFromReconciliation based on whether priority-0 android_camera
    // + android_microphone inputs are registered with the ffstream-camera
    // daemon (port 3594). On success, also auto-applies the built-in camera
    // publisher URL + switchOutput to the camera daemon so a Wingout restart
    // re-attaches without a re-tap. Mirrors reconcileWithFFStream above but
    // is a dedicated function because:
    //   1. Per-client retry/epoch state must not be shared.
    //   2. The camera-side reconcile alone drives setActiveFromReconciliation.
    //      Sharing the body with the streaming
    //      client's reconcile would reintroduce active-state ownership ambiguity
    //      or require an identity-check branch that obscures intent.
    function reconcileWithFFStreamCamera(ffstreamCameraClient) {
        if (!ffstreamCameraClient.isChannelReady()) {
            return;
        }
        var capturedEpoch = streamingSettings.userIntentEpoch;
        var capturedChannelEpoch = main.reconcileCameraChannelEpoch;
        ffstreamCameraClient.getInputsInfo(
            function(reply) {
                var inputs = reply.inputsData || reply.inputs || []
                var hasCam = false, hasMic = false
                for (var i = 0; i < inputs.length; ++i) {
                    var inp = inputs[i]
                    if ((inp.priority || 0) !== 0) continue
                    var opts = (inp.inputConfig && (inp.inputConfig.customOptionsData || inp.inputConfig.customOptions))
                               ? (inp.inputConfig.customOptionsData || inp.inputConfig.customOptions) : []
                    for (var j = 0; j < opts.length; ++j) {
                        if (opts[j].key !== "f") continue
                        if (opts[j].value === "android_camera") hasCam = true
                        else if (opts[j].value === "android_microphone") hasMic = true
                    }
                }
                streamingSettings.setActiveFromReconciliation(hasCam && hasMic, capturedEpoch)
                main.reconcileCameraRetryDelayMs = 2000;
                if (!(hasCam && hasMic)) {
                    console.log("Main.qml: camera reconcile says inactive — skipping auto-apply switchOutput");
                    return;
                }
                var cameraVideoCodec = main.enforceRequiredVideoCodec();
                console.log("Main.qml: ffstreamCameraClient channel ready, applying codec",
                    cameraVideoCodec,
                    streamingSettings.width + "x" + streamingSettings.height,
                    streamingSettings.bitrateKbps + "kbps",
                    streamingSettings.audioCodec,
                    streamingSettings.audioSampleRate + "Hz",
                    streamingSettings.audioBitrateKbps + "kbps",
                    "max=" + streamingSettings.maxBitrateKbps + "kbps");
                // Push the upstream-supervisor PUBLISHER URL (publisher
                // port + template tokens), NOT streamingSettings.outputUrl.
                // The latter is the CONSUMER URL (consumer port /
                // "<stem>-merged") and would be rejected by the
                // supervisor's publisher regex, wedging the libav RTMP
                // open. See builtinCameraPublisherUrl() comment.
                var cameraPublisherUrl = main.builtinCameraPublisherUrl();
                if (cameraPublisherUrl && cameraPublisherUrl.length > 0) {
                    ffstreamCameraClient.setOutputUrl(
                        cameraPublisherUrl,
                        function(reply2) {
                            console.log("Main.qml: camera auto setOutputUrl ok");
                        },
                        function(error) {
                            console.warn("Main.qml: camera auto setOutputUrl failed:", JSON.stringify(error));
                        },
                        main.grpcCallOptions);
                }
                ffstreamCameraClient.switchOutput(
                    cameraVideoCodec,
                    streamingSettings.width,
                    streamingSettings.height,
                    streamingSettings.bitrateKbps * 1000,
                    streamingSettings.audioCodec,
                    streamingSettings.audioSampleRate,
                    streamingSettings.audioBitrateKbps * streamingSettings.audioChannels * 1000,
                    streamingSettings.maxBitrateKbps * 1000,
                    function(reply2) {
                        console.log("Main.qml: camera auto switchOutput ok");
                    },
                    function(error) {
                        console.warn("Main.qml: camera auto switchOutput failed");
                        main.processFFStreamGRPCError(ffstreamCameraClient, error);
                    },
                    main.grpcCallOptions);
            },
            function(error) {
                console.warn("Main.qml: camera reconcile getInputsInfo failed:",
                             JSON.stringify(error))
                main.processFFStreamGRPCError(ffstreamCameraClient, error)
                if (capturedChannelEpoch !== main.reconcileCameraChannelEpoch) {
                    console.log("Main.qml: camera reconcile failure dropped — channel epoch advanced",
                                capturedChannelEpoch, "->", main.reconcileCameraChannelEpoch);
                    return;
                }
                if (!ffstreamCameraClient.isChannelReady()) {
                    return;
                }
                reconcileCameraRetryTimer.interval = main.reconcileCameraRetryDelayMs;
                main.reconcileCameraRetryDelayMs =
                    Math.min(main.reconcileCameraRetryDelayMs * 2, main.reconcileRetryMaxMs);
                console.log("Main.qml: camera reconcile retry scheduled in",
                            reconcileCameraRetryTimer.interval, "ms (next delay",
                            main.reconcileCameraRetryDelayMs, "ms)");
                reconcileCameraRetryTimer.restart();
            },
            main.grpcCallOptions);
    }

    Connections {
        target: ffstreamCameraClient
        function onChannelChanged() {
            main.reconcileCameraChannelEpoch++;
            if (!ffstreamCameraClient.isChannelReady()) {
                console.log("Main.qml: ffstreamCameraClient channelChanged but channel not ready yet");
                reconcileCameraRetryTimer.stop();
                return;
            }
            main.reconcileCameraRetryDelayMs = 2000;
            reconcileCameraRetryTimer.stop();
            main.reconcileWithFFStreamCamera(ffstreamCameraClient);
        }
    }

    Connections {
        target: main
        function onNormalizedFFStreamHostChanged() {
            if (main.normalizedFFStreamHost && main.normalizedFFStreamHost.length > 0) {
                ffstreamClient.setServerUri(main.normalizedFFStreamHost);
                console.log("ffstreamClient setServerUri:", main.normalizedFFStreamHost);
            }
        }
    }

    function processStreamDGRPCError(dxProducer, error) {
        console.log("StreamD gRPC error:", JSON.stringify(error));
        if (dxProducer.processGRPCError !== undefined) {
            dxProducer.processGRPCError(error);
        }
    }

    function processFFStreamGRPCError(ffstream, error) {
        console.log("FFStream gRPC error:", JSON.stringify(error));
        if (ffstream.processGRPCError !== undefined) {
            ffstream.processGRPCError(error);
        }
    }

    // fireMultiPlatformRPC fires an RPC across all platforms with shared
    // success/error counting and status reporting.
    //   label: display name (e.g. "Shoutout", "Raid", "Title")
    //   rpcCall: function(platID, onSuccess, onError) that initiates the RPC
    //   setStatus: function(text) to update status text
    //   setStatusColor: function(colorStr) to update status color
    function fireMultiPlatformRPC(label, rpcCall, setStatus, setStatusColor) {
        var platforms = ["twitch", "youtube", "kick"];
        setStatus("Sending " + label.toLowerCase() + "...");
        setStatusColor("#FFFF00");
        var successCount = 0;
        var errorCount = 0;
        var total = platforms.length;
        for (var i = 0; i < platforms.length; i++) {
            (function(platID) {
                rpcCall(platID,
                    function() {
                        successCount++;
                        if (successCount + errorCount === total) {
                            setStatus(label + " sent (" + successCount + "/" + total + " ok)");
                            setStatusColor(errorCount === 0 ? "#00FF00" : "#FFFF00");
                        }
                    },
                    function(error) {
                        errorCount++;
                        console.warn(label + " failed for", platID, error);
                        if (successCount + errorCount === total) {
                            setStatus(successCount > 0
                                ? label + " partial (" + successCount + "/" + total + ")"
                                : label + " failed");
                            setStatusColor(successCount > 0 ? "#FFFF00" : "#FF0000");
                        }
                        processStreamDGRPCError(dxProducerClient, error);
                    });
            })(platforms[i]);
        }
    }

    function checkStreamDClient() {
        if (!dxProducerClient) {
            console.warn("Main.qml: StreamD client not initialized");
            return false;
        }
        return true;
    }

    function checkFFStreamClient() {
        if (!ffstreamClient) {
            console.warn("Main.qml: FFStream client not initialized");
            return false;
        }
        return true;
    }

    function withStreamClient(callback, onError, caller) {
        if (!dxProducerClient) {
            console.warn("Main.qml: StreamD client not initialized");
            if (onError) {
                onError("client not initialized");
            }
            return;
        }
        if (!dxProducerClient.isChannelReady()) {
            if (onError) {
                onError("channel not ready");
            }
            return;
        }
        callback(dxProducerClient);
    }

    function withFFStreamClient(callback, onError) {
        if (!ffstreamClient) {
            console.warn("Main.qml: FFStream client not initialized");
            if (onError) {
                onError("client not initialized");
            }
            return;
        }
        callback(ffstreamClient);
    }

    Connections {
        target: main.applicationWindow
        function onClosing(close) {
            close.accepted = false;
            main.locked = true;
        }
    }

    // Default preview RTMP URL. We do not seed a deployment-specific
    // stream path here: the consumer URL stem is a deployment choice
    // (mediamtx route, AVD merged-route, etc.), and any non-empty
    // default would presume one specific deployment. First-run users
    // configure their own preview URL via InitialSetup or Settings; an
    // empty result here keeps the dashboard preview blank until they do.
    function defaultPreviewRtmpUrl() {
        return "";
    }

    // Publisher URL for the built-in camera daemon's setOutputUrl. The
    // upstream supervisor (avd) accepts publishers on its publisher
    // port only when the path includes the template tokens
    // ${v:0:codec}, ${a:0:codec}, ${v:0:height}, ${a:0:rate} (LITERAL
    // ffstream placeholders, expanded by the daemon at output-open
    // time). The supervisor then re-publishes on its consumer port at
    // "<endpoint>-merged" for downstream readers / ffprobe.
    //
    // Strategy: DERIVE FROM streamingSettings.outputUrl rather than from
    // appSettings.dxProducerHost. The latter can point at the on-device
    // gRPC loopback instead of the LAN host that accepts media
    // publishers. The user's outputUrl already encodes the correct
    // media host:port + endpoint stem (e.g.
    // "rtmp://192.0.2.10:1945/<route>/<stem>-merged"); we
    // transform consumer-port 1945 → publisher-port 1946 and replace the
    // "-merged" suffix with template tokens.
    //
    // Used by:
    //   - reconcileWithFFStreamCamera() auto-apply on wingout restart.
    //   - CamerasBuiltin.qml _doActivate() leg 3 (SetOutputURL).
    //
    // Not used for ffstreamClient (port 3593, mediamtx-side): that daemon
    // gets streamingSettings.outputUrl directly because the user's
    // CONSUMER URL is what mediamtx-side ffstream republishes to.
    //
    // Returns "" if the user's outputUrl is missing or malformed; callers
    // skip the setOutputUrl RPC in that case (the visible Activate dialog
    // surfaces SetOutputURL failures in the absence of a sensible default).
    function builtinCameraPublisherUrl() {
        var raw = streamingSettings ? streamingSettings.outputUrl : "";
        if (!raw || raw.length === 0) {
            return "";
        }
        var s = String(raw);
        // Already publisher-form (contains the literal ffstream template
        // tokens)? Pass through unchanged. Defends against the persisted
        // outputUrl having been pre-baked with the publisher template, in
        // which case there is nothing to transform — re-running the
        // -merged regex would fail and we'd push "" to the daemon.
        if (s.indexOf("${v:0:codec}") !== -1
                || s.indexOf("${a:0:codec}") !== -1
                || s.indexOf("${v:0:height}") !== -1
                || s.indexOf("${a:0:rate}") !== -1) {
            return s;
        }
        // Consumer form: rtmp://host[:port]/<path>-merged[/]
        // Group 1 = host (no port), 2 = port (optional), 3 = path stem
        // up to the "-merged" suffix.
        var m = s.match(/^rtmp:\/\/([^\/:]+)(?::(\d+))?\/(.+?)-merged\/?$/);
        if (!m) {
            console.warn("Main.qml: outputUrl does not match expected "
                         + "rtmp://host[:port]/<stem>-merged shape and is "
                         + "not already in publisher template form; cannot "
                         + "derive publisher URL: " + s);
            return "";
        }
        var host = m[1];
        var pathStem = m[3];
        return "rtmp://" + host + ":1946/" + pathStem
               + "-${v:0:codec}${a:0:codec}-"
               + "${v:0:height}${a:0:rate}/";
    }

    Component.onCompleted: {
        console.log("Platform object type:", platform);
        if (platform && typeof platform.refreshWiFiState === 'function')
            platform.refreshWiFiState();
        if (appSettings && (!appSettings.previewRTMPUrl || appSettings.previewRTMPUrl.length === 0)) {
            var seed = defaultPreviewRtmpUrl();
            if (seed && seed.length > 0) {
                appSettings.previewRTMPUrl = seed;
                console.log("Main.qml: seeded default previewRTMPUrl:", appSettings.previewRTMPUrl);
            }
        }
    }

    StreamD.Client {
        id: dxProducerClient
        Component.onCompleted: {
            if (main.normalizedDxProducerHost && main.normalizedDxProducerHost.length > 0) {
                dxProducerClient.setServerUri(main.normalizedDxProducerHost);
                console.log("dxProducerClient setServerUri:", main.normalizedDxProducerHost);
            }
        }
    }

    Connections {
        target: main
        function onNormalizedDxProducerHostChanged() {
            if (main.normalizedDxProducerHost && main.normalizedDxProducerHost.length > 0) {
                dxProducerClient.setServerUri(main.normalizedDxProducerHost);
                console.log("dxProducerClient setServerUri:", main.normalizedDxProducerHost);
            }
        }
    }

    StackLayout {
        id: stack
        objectName: "stack"
        anchors.fill: parent
        currentIndex: 0

        Dashboard {
            id: dashboardPage
            root: main
        }
        Cameras {
            id: camerasPage
            root: main
        }
        DJIControl {
            id: djiControlPage
            root: main
            Component.onCompleted: console.log("DJIControl page completed")
        }
        Chat {
            id: chatPage
            root: main
        }
        Players {
            id: playersPage
            root: main
        }
        Restreams {
            id: restreamsPage
            root: main
        }
        Monitor {
            id: monitorPage
            root: main
        }
        Profiles {
            id: profilesPage
            root: main
        }
        Settings {
            id: settingsPage
            root: main
            appSettings: main.appSettings
        }
    }

    RoundButton {
        id: menuButton
        objectName: "menuButton"
        text: "☰"
        anchors.top: parent.top
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: 56
        height: 56
        font.pixelSize: 24
        z: 100
        highlighted: true
        Material.elevation: 6
        onClicked: navMenu.open()
    }

    Menu {
        id: navMenu
        y: menuButton.y + menuButton.height
        x: menuButton.x - (width / 2) + (menuButton.width / 2)

        MenuItem {
            text: "Dashboard"
            onTriggered: stack.currentIndex = 0
        }
        MenuItem {
            text: "Cameras"
            onTriggered: stack.currentIndex = 1
        }
        MenuItem {
            text: "DJI"
            onTriggered: stack.currentIndex = 2
        }
        MenuItem {
            text: "Chat"
            onTriggered: stack.currentIndex = 3
        }
        MenuItem {
            text: "Players"
            onTriggered: stack.currentIndex = 4
        }
        MenuItem {
            text: "Restreams"
            onTriggered: stack.currentIndex = 5
        }
        MenuItem {
            text: "Monitor"
            onTriggered: stack.currentIndex = 6
        }
        MenuItem {
            text: "Profiles"
            onTriggered: stack.currentIndex = 7
        }
        MenuItem {
            text: "Settings"
            onTriggered: stack.currentIndex = 8
        }
    }

    SwipeLockOverlay {
        id: lockOverlay
        locked: main.locked
        topPadding: main.safeAreaTop
        onUnlockRequested: main.locked = false
    }

    Button {
        id: lockButton
        objectName: "lockButton"
        visible: !main.locked && stack.currentIndex === 0
        text: "🔒"
        anchors.top: stack.top
        anchors.right: stack.right
        anchors.margins: 16
        font.pixelSize: 40
        property real defaultOpacity: 0.7
        opacity: hovered ? 1.0 : defaultOpacity
        onClicked: main.locked = true
    }
}
