/* This file implements the CamerasBuiltin component for managing local camera settings.
 *
 * SCOPE INVARIANT:
 *   ALL multi-step helper functions (_removeBuiltinInputsAtPriority0,
 *   _purgeBuiltinInputs, _doActivate, _doDeactivate, _rollbackPriority0,
 *   _withEpoch, …)
 *   live at top-level `builtin` scope rather than nested inside a Button's
 *   onClicked block. Helpers used by both Activate and Deactivate must stay
 *   reachable from both buttons, especially now that Wingout configures the
 *   dedicated ffstream-camera daemon instead of owning the mediamtx-side
 *   daemon.
 *   Pinned by: tests/qml/tst_cameras_builtin_activation_lifecycle.qml
 *   test_11_helpers_hoisted_to_top_level.
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import StreamingSettingsController
import WingOut

ColumnLayout {
    id: builtin
    spacing: 8

    // Test seam: expose deactivateErrorDialog via a property alias so the
    // wingout QML test harness can assert dialog.visible after
    // _showDeactivateError(detail). QML ids are file-local; without the
    // alias the test cannot read the dialog state from outside. No production
    // caller reads this property; the alias is observation-only.
    property alias deactivateErrorDialog: deactivateErrorDialog

    // Test seam (B2 watchdog tests): expose activationWatchdog +
    // activationTimeoutDialog via aliases so
    // tst_cameras_builtin_activation_lifecycle.qml can drive the
    // Timer's interval / read .running and assert dialog visibility
    // without reaching across QML id scope. Same observation-only
    // contract as deactivateErrorDialog above.
    property alias activationWatchdog: activationWatchdog
    property alias activationTimeoutDialog: activationTimeoutDialog
    // Expose activateErrorDialog so tests can assert the dialog opens for
    // visible error codes and stays closed for filtered codes. Same
    // observation-only seam contract as the other dialog aliases.
    property alias activateErrorDialog: activateErrorDialog
    property alias cameraDaemonStoppedDialog: cameraDaemonStoppedDialog
    property alias videoCodecModel: codecModel
    property string codecResetNotice: ""

    // UX feedback (Activate/Deactivate latency bug): an Activate or
    // Deactivate tap kicks off a multi-leg gRPC chain that can take
    // several seconds end-to-end against a healthy daemon, and forever
    // against a wedged or unreachable one (the QML callsites pass a null
    // QGrpcCallOptions, so there is no per-call deadline). Without a
    // visible in-flight cue the user saw absolutely nothing happen for
    // several seconds after tapping and assumed the button did not
    // register — leading to confused double-taps and trapped UI.
    //
    // _activationInFlight: true between tap and any terminal callback
    //   (success commit, error dialog, permission denied, no-client
    //   early-return, watchdog timeout). Drives the BusyIndicator next
    //   to the status label, the "Activating…" / "Deactivating…" label
    //   text, and the Activate/Deactivate buttons' enabled state.
    // _activationVerb: "Activating" or "Deactivating" — the present-
    //   continuous form used in the status label while in-flight.
    //
    // The flag is mutated only via _beginActivation(verb) /
    // _endActivation() so the watchdog Timer's start/stop is paired
    // with the flag transition in one place; every terminal path
    // therefore needs only to call _endActivation() and cannot leak a
    // running timer.
    property bool _activationInFlight: false
    property string _activationVerb: ""

    // Chain-epoch counter. Bumped at every _beginActivation tap and
    // captured by every dispatched callback so a callback from a
    // PREVIOUSLY-aborted chain (watchdog fired, user dismissed dialog,
    // user re-tapped, then the original wedged gRPC reply finally
    // arrives) does NOT mutate state on the CURRENT chain — neither
    // calling _endActivation() (which would clear the new spinner
    // mid-flight) nor opening an error dialog stamped against a
    // long-since-discarded chain. The per-RPC 10s deadline should kill
    // wedged calls before any user re-tap on a 30s dismiss-and-retry
    // timeline, so this epoch is belt-and-suspenders for delayed replies
    // that outlive their original chain.
    property int _activationEpoch: 0

    // Watchdog interval: how long the in-flight cue persists before the
    // belt-and-suspenders timeout dialog opens. Normal activation RPCs
    // use builtin.root.grpcCallOptions; readiness probes use a shorter
    // dedicated deadline because they are retry-loop probes, not user
    // operations. The derived probe budget below must stay below this
    // watchdog so a stopped daemon gets a retryable visible error before
    // the generic activation timeout fires.
    readonly property int activationWatchdogMs: 30000
    readonly property int ffstreamCameraStartupProbeDeadlineMs:
        builtin.root && builtin.root.ffstreamCameraStartupProbeGrpcCallOptions
        && builtin.root.ffstreamCameraStartupProbeGrpcCallOptions.deadlineTimeout !== undefined
        ? builtin.root.ffstreamCameraStartupProbeGrpcCallOptions.deadlineTimeout : 400
    property int ffstreamCameraStartupProbeAttempts:
        builtin.root && builtin.root.ffstreamCameraStartupProbeAttempts !== undefined
        ? builtin.root.ffstreamCameraStartupProbeAttempts : 20
    property int ffstreamCameraStartupProbeIntervalMs:
        builtin.root && builtin.root.ffstreamCameraStartupProbeIntervalMs !== undefined
        ? builtin.root.ffstreamCameraStartupProbeIntervalMs : 500
    readonly property int ffstreamCameraStartupProbeBudgetMs:
        ffstreamCameraStartupProbeAttempts
        * (ffstreamCameraStartupProbeDeadlineMs
           + ffstreamCameraStartupProbeIntervalMs)
    property var _ffstreamCameraReadyCallback: null
    property int _ffstreamCameraReadyEpoch: 0
    property int _ffstreamCameraReadyAttemptsLeft: 0
    property bool _ffstreamCameraDaemonKnownStopped: false
    property int _ffstreamCameraDeactivateIdleEpoch: 0
    property int _ffstreamCameraDeactivateIdleAttemptsLeft: 0

    // Proactive ffstream-camera gRPC reachability monitor (Task #124).
    //
    // Background: prior to this monitor, the only daemon-reachability check
    // fired during _ensureFFStreamCameraDaemonReady — that is, ONLY when
    // the user tapped Activate. If the camera daemon was unreachable when
    // the page opened, the Activate button stayed enabled and the user's
    // tap fired the multi-leg gRPC chain into the void with no feedback
    // (Task #116 RC: "qt.grpc : No channel(s) attached" log flood, no UI
    // surface). The monitor below probes the daemon continuously while the
    // page is visible and not mid-Activate, debounces transient drops with
    // a grace window, then flips _backendReachable + opens
    // gRPCBackendUnreachableDialog so the user knows what to fix.
    //
    // _grpcProbeIntervalMs / _grpcUnreachableGraceMs are exposed as test
    // seams: the QML test (tst_cameras_builtin_grpc_no_channel.qml) sets
    // them to short values (50 ms / 200 ms) so it does not need multi-
    // second wall-clock waits to exercise the live Timer machinery.
    // Production defaults stay at 1 s / 2 s.
    //
    // _grpcFirstFailureMs tracks the start of the current failure streak.
    // Zero means "no failure pending"; any non-zero timestamp marks the
    // tick on which the streak began. A successful probe clears it back
    // to zero, debouncing transient hiccups without flipping the flag.
    property int _grpcProbeIntervalMs: 1000
    property int _grpcUnreachableGraceMs: 2000
    property bool _backendReachable: true
    property real _grpcFirstFailureMs: 0
    property alias gRPCBackendUnreachableDialog: gRPCBackendUnreachableDialog
    // Test-only opt-out for the proactive monitor: tests that exercise the
    // user-intent-bound getInputsInfo callsites (Activate / Deactivate
    // probes) and assert exact call counts must disable the proactive
    // monitor or its tick would inflate the count and consume queued
    // stub responses meant for the user-intent path. Production never
    // sets this to false; the property exists so a test can pass it via
    // createTemporaryObject's initial-properties dictionary.
    property bool _grpcProbeEnabled: true

    // Test seam (#17 fix): expose outputUrlField via an alias so the
    // regression test (tst_cameras_builtin_outputurl_commit.qml) can
    // drive its text/focus directly and assert that mid-edit text
    // changes are NOT propagated to settingsController.outputUrl
    // until onEditingFinished fires (focus loss / Enter). This is the
    // contract that prevents the per-keystroke writeToFile that
    // mangled the persisted URL pre-fix.
    property alias outputUrlField: outputUrlField

    // Test seam (#15 second-tap fix): expose settingsScroll so the
    // regression test (tst_cameras_builtin_scroll_target.qml) can
    // drive _computeScrollTarget directly. The bug only reproduces on
    // a real Android phone with a real IME — without a test seam, the
    // RED→GREEN protocol can't be enforced via the headless test
    // harness. Exposing the ScrollView lets the test exercise the
    // pure scroll-math helper with the exact phone-captured values.
    property alias settingsScroll: settingsScroll

    // Bridge to QPermissions for runtime CAMERA + RECORD_AUDIO requests.
    // The android_camera / android_microphone demuxers refuse to open
    // without these, so we must prompt before issuing addInput.
    AndroidPermissions {
        id: androidPermissions
    }

    // Surfaced when the user denies one of the permissions required to
    // capture from the built-in camera/mic. Educates them that they need
    // to enable it via Settings before re-tapping Activate.
    MessageDialog {
        id: permDeniedDialog
        title: "Permission required"
        property string missing: ""
        text: "Wing Out needs " + missing + " permission to capture from the "
              + "built-in camera. Grant it in the OS Settings, then tap "
              + "Activate again."
        buttons: MessageDialog.Ok
    }

    // Surfaced on AddInput RPC failure during Activate. The user
    // asked that errors NOT be silent; we keep m_active=false
    // (we never called settingsController.activate() on this path)
    // and show what failed and the gRPC status text.
    MessageDialog {
        id: activateErrorDialog
        title: "Activation failed"
        property string leg: ""
        property string detail: ""
        text: leg + " could not be activated.\n\n" + detail
              + "\n\nFix the issue and tap Activate again."
        buttons: MessageDialog.Ok
    }

    MessageDialog {
        id: cameraDaemonStoppedDialog
        title: "Camera daemon stopped"
        property string detail: ""
        text: "The ffstream-camera daemon is stopped or unreachable.\n\n"
              + detail + "\n\nTap Activate again after it reconnects."
        buttons: MessageDialog.Ok
    }

    // Surfaced when the proactive gRPC reachability monitor observes
    // failures persisting beyond _grpcUnreachableGraceMs (Task #124,
    // F-task116-3). Distinct from cameraDaemonStoppedDialog (which fires
    // on Activate-tap startup probe exhaustion) and from activateErrorDialog
    // (which fires on a specific RPC leg failure mid-chain): this dialog
    // surfaces a STATE problem that is true regardless of whether the user
    // tapped Activate. The text identifies the supervisor as the recovery
    // surface (matching the actual ownership: the rc.local-owned supervisor
    // restarts the ffstream-camera loop script after device reboot).
    MessageDialog {
        id: gRPCBackendUnreachableDialog
        title: "ffstream backend unreachable"
        text: "The ffstream-camera daemon is not responding over gRPC.\n\n"
              + "Please launch the ffstream-camera supervisor on the phone "
              + "(or reboot the device so rc.local restarts it) before "
              + "tapping Activate."
        buttons: MessageDialog.Ok
    }

    // Surfaced on Deactivate when the ffstream-camera End RPC fails before
    // Wing Out can prove that the daemon stopped. Keep Active state intact so
    // the user can retry the stop instead of recording a false inactive state.
    MessageDialog {
        id: deactivateErrorDialog
        title: "Deactivate failed"
        property string detail: ""
        text: "Wing Out sent the ffstream-camera stop command, but it did "
              + "not complete cleanly.\n\n" + detail
              + "\n\nThe camera remains marked Active so you can retry "
              + "Deactivate."
        buttons: MessageDialog.Ok
    }

    function _showDeactivateError(detail) {
        if (!detail || String(detail).length <= 0) return
        deactivateErrorDialog.detail = String(detail)
        deactivateErrorDialog.open()
    }

    // Surfaced when the Activate/Deactivate gRPC chain has not produced
    // a terminal callback within activationWatchdog.interval ms. The
    // dominant cause is the ffstream-camera daemon being down or the
    // gRPC channel wedged: with a null QGrpcCallOptions on every leg
    // the call has no per-RPC deadline, so the in-flight flag would
    // otherwise stay set forever and the spinner would spin forever.
    // The watchdog forces a user-visible failure path so the UI is
    // recoverable: the spinner clears, the buttons re-enable, and this
    // dialog explains what happened and what to try.
    MessageDialog {
        id: activationTimeoutDialog
        title: "Operation timed out"
        text: "The Activate/Deactivate request did not complete within "
              + "30 seconds. The ffstream-camera daemon may be unreachable. "
              + "Try again, or check that the daemon is running."
        buttons: MessageDialog.Ok
        // B6 NIT note: an explicit closePolicy was considered (Escape +
        // press-outside) but QtQuick.Dialogs.MessageDialog
        // (QQuickAbstractDialog subclass) does not expose closePolicy;
        // it routes through the platform-native dialog helper which
        // owns dismiss semantics. Adding `closePolicy: Popup.*` is a
        // QML compile error here. The native dialog already supports
        // back-gesture and OK-button dismissal on Android, which is
        // the user-visible contract. Documented as deferred / N/A so
        // a future reviewer doesn't re-litigate it.
    }

    // Watchdog: started by _beginActivation(verb), stopped by
    // _endActivation() on any normal terminal path. interval=30000 ms is
    // well above a healthy round-trip (the 4-leg Activate chain
    // typically completes in <2 s on a reachable daemon) but short
    // enough that the user is not stranded for more than half a minute
    // on a wedged daemon. On timeout we clear the in-flight flag
    // ourselves (so the button row re-enables and the spinner hides)
    // and open activationTimeoutDialog.
    Timer {
        id: activationWatchdog
        interval: builtin.activationWatchdogMs
        repeat: false
        onTriggered: {
            if (!builtin._activationInFlight) return
            builtin._activationInFlight = false
            builtin._activationVerb = ""
            activationTimeoutDialog.open()
        }
    }

    Timer {
        id: ffstreamCameraStartupProbeTimer
        interval: builtin.ffstreamCameraStartupProbeIntervalMs
        repeat: false
        onTriggered: {
            builtin._probeFFStreamCameraDaemon(
                builtin._ffstreamCameraReadyEpoch,
                builtin._ffstreamCameraReadyAttemptsLeft,
                builtin._ffstreamCameraReadyCallback)
        }
    }

    Timer {
        id: ffstreamCameraDeactivateIdleProbeTimer
        interval: builtin.ffstreamCameraStartupProbeIntervalMs
        repeat: false
        onTriggered: {
            builtin._probeDeactivateIdle(
                builtin._ffstreamCameraDeactivateIdleEpoch,
                builtin._ffstreamCameraDeactivateIdleAttemptsLeft)
        }
    }

    // Proactive ffstream-camera gRPC reachability monitor (Task #124).
    //
    // Tick cadence: builtin._grpcProbeIntervalMs (default 1 s). Each tick
    // sends a getInputsInfo RPC and either clears the failure streak (on
    // success) or extends it (on failure). When the streak duration
    // exceeds builtin._grpcUnreachableGraceMs (default 2 s) the monitor
    // flips builtin._backendReachable=false and opens
    // gRPCBackendUnreachableDialog. The first success after a flip
    // restores the flag and dismisses the dialog so the user does not
    // have to interact with it on recovery.
    //
    // Suspended while builtin._activationInFlight is true: the Activate
    // chain already issues its own getInputsInfo probe via
    // _ensureFFStreamCameraDaemonReady plus four more RPCs (AddInput x2,
    // SetOutputURL, SwitchOutput); a parallel proactive probe would
    // double round-trip pressure during the most latency-sensitive moment
    // of the UI and risk reorder bugs.
    //
    // triggeredOnStart=true so the first tick fires immediately rather
    // than after one full interval — keeps the initial reachable
    // determination fast on page entry.
    Timer {
        id: gRPCBackendReachabilityProbeTimer
        interval: builtin._grpcProbeIntervalMs
        repeat: true
        running: builtin._grpcProbeEnabled && !builtin._activationInFlight
        triggeredOnStart: true
        onTriggered: builtin._performBackendReachabilityProbe()
    }

    function _backendReachabilityProbeOptions() {
        if (builtin.root
                && builtin.root.ffstreamCameraReachabilityProbeGrpcCallOptions) {
            return builtin.root.ffstreamCameraReachabilityProbeGrpcCallOptions
        }
        if (builtin.root && builtin.root.ffstreamCameraStartupProbeGrpcCallOptions) {
            return builtin.root.ffstreamCameraStartupProbeGrpcCallOptions
        }
        return builtin.root ? builtin.root.grpcCallOptions : null
    }

    function _onBackendReachabilityProbeSuccess() {
        builtin._grpcFirstFailureMs = 0
        if (!builtin._backendReachable) {
            builtin._backendReachable = true
        }
        if (gRPCBackendUnreachableDialog.visible) {
            gRPCBackendUnreachableDialog.close()
        }
    }

    function _onBackendReachabilityProbeFailure() {
        var nowMs = Date.now()
        if (builtin._grpcFirstFailureMs === 0) {
            builtin._grpcFirstFailureMs = nowMs
            return
        }
        if (nowMs - builtin._grpcFirstFailureMs
                < builtin._grpcUnreachableGraceMs) {
            // Inside the grace window — keep the reachable flag and
            // dialog state untouched. Transient blips are invisible to
            // the user by design.
            return
        }
        if (builtin._backendReachable) {
            builtin._backendReachable = false
        }
        if (!gRPCBackendUnreachableDialog.visible) {
            gRPCBackendUnreachableDialog.open()
        }
    }

    function _performBackendReachabilityProbe() {
        if (!builtin.root || !builtin.root.ffstreamCameraClient) return
        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        if (typeof ffstreamCameraClient.getInputsInfo !== "function") return
        if (builtin.root.ffstreamCameraHost
                && typeof ffstreamCameraClient.setServerUri === "function") {
            ffstreamCameraClient.setServerUri(builtin.root.ffstreamCameraHost)
        }
        ffstreamCameraClient.getInputsInfo(
            function(_) { builtin._onBackendReachabilityProbeSuccess() },
            function(_) { builtin._onBackendReachabilityProbeFailure() },
            builtin._backendReachabilityProbeOptions())
    }

    function _showCameraDaemonStoppedError(detail) {
        cameraDaemonStoppedDialog.detail = detail
            || "The ffstream-camera daemon is not reachable. It is started "
               + "by device boot services, not by Wing Out."
        cameraDaemonStoppedDialog.open()
        builtin._endActivation()
    }

    // Routes a configuration-error early-return through the existing
    // activateErrorDialog (Task #124, F-task116-3 Pool C re-author).
    // Used by _doActivate when the publisher URL is empty (and similar
    // pre-RPC validation failures) so the user-visible failure path is
    // identical to the mid-chain leg-failure path: same dialog, same
    // "Fix the issue and tap Activate again." footer, parameterised by
    // a leg label so the user can identify which field is missing.
    // Always clears the in-flight cue so the user is not stranded with
    // a permanent "Activating…" label.
    function _showActivateConfigurationError(legLabel, detail) {
        builtin._endActivation()
        activateErrorDialog.leg = legLabel
        activateErrorDialog.detail = String(detail
            || "Missing streaming configuration.")
        activateErrorDialog.open()
    }

    function _ffstreamCameraStartupProbeOptions() {
        if (builtin.root && builtin.root.ffstreamCameraStartupProbeGrpcCallOptions) {
            return builtin.root.ffstreamCameraStartupProbeGrpcCallOptions
        }
        return builtin.root ? builtin.root.grpcCallOptions : null
    }

    function cameraIndexForPreferredCamera(camera) {
        return camera === "Back" ? 0 : 1
    }

    function _ensureFFStreamCameraDaemonReady(epoch, onReady) {
        if (!builtin.root || !builtin.root.ffstreamCameraClient) {
            onReady()
            return
        }
        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        if (builtin.root.ffstreamCameraHost
                && typeof ffstreamCameraClient.setServerUri === "function") {
            ffstreamCameraClient.setServerUri(builtin.root.ffstreamCameraHost)
        }
        ffstreamCameraClient.getInputsInfo(
            builtin._withEpoch(epoch, function(_) {
                builtin._ffstreamCameraDaemonKnownStopped = false
                onReady()
            }),
            builtin._withEpoch(epoch, function(err) {
                if (typeof ffstreamCameraClient.processGRPCError === "function") {
                    ffstreamCameraClient.processGRPCError(err)
                }
                builtin._probeFFStreamCameraDaemon(
                    epoch,
                    builtin.ffstreamCameraStartupProbeAttempts,
                    onReady)
            }),
            builtin._ffstreamCameraStartupProbeOptions())
    }

    function _scheduleFFStreamCameraProbe(epoch, attemptsLeft, onReady) {
        if (attemptsLeft <= 0) {
            builtin._showCameraDaemonStoppedError(
                "The ffstream-camera daemon did not become reachable. "
                + "The camera supervisor is owned by rc.local. On the test "
                + "phone, recover Ubuntu from the test harness with "
                + "/data/ubuntu/start.sh; on production, reboot to apply "
                + "rc.local after deployment.")
            return
        }
        builtin._ffstreamCameraReadyEpoch = epoch
        builtin._ffstreamCameraReadyAttemptsLeft = attemptsLeft
        builtin._ffstreamCameraReadyCallback = onReady
        ffstreamCameraStartupProbeTimer.restart()
    }

    function _probeFFStreamCameraDaemon(epoch, attemptsLeft, onReady) {
        if (!builtin._isCurrentEpoch(epoch)) return
        if (!builtin.root || !builtin.root.ffstreamCameraClient) {
            onReady()
            return
        }
        if (attemptsLeft <= 0) {
            builtin._scheduleFFStreamCameraProbe(epoch, 0, onReady)
            return
        }

        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        if (builtin.root.ffstreamCameraHost
                && typeof ffstreamCameraClient.setServerUri === "function") {
            ffstreamCameraClient.setServerUri(builtin.root.ffstreamCameraHost)
        }

        ffstreamCameraClient.getInputsInfo(
            builtin._withEpoch(epoch, function(_) {
                builtin._ffstreamCameraDaemonKnownStopped = false
                onReady()
            }),
            builtin._withEpoch(epoch, function(err) {
                if (typeof ffstreamCameraClient.processGRPCError === "function") {
                    ffstreamCameraClient.processGRPCError(err)
                }
                if (attemptsLeft <= 1) {
                    builtin._scheduleFFStreamCameraProbe(epoch, 0, onReady)
                    return
                }
                builtin._scheduleFFStreamCameraProbe(
                    epoch, attemptsLeft - 1, onReady)
            }),
            builtin._ffstreamCameraStartupProbeOptions())
    }

    // Centralised in-flight transitions. Using a function (instead of
    // mutating _activationInFlight at each callsite) keeps the watchdog
    // start/stop paired with the flag in one place — every terminal
    // path can call _endActivation() without remembering to stop the
    // watchdog separately, and every entry point calls _beginActivation
    // synchronously on the UI thread so the spinner appears within one
    // frame of the tap.
    //
    // _endActivation() is no-op if the flag is already false: the
    // watchdog onTriggered path clears the flag itself before opening
    // its dialog, and a subsequent normal callback (race: chain
    // completes JUST after the 30 s mark) must not flip the flag back
    // on or restart the timer.
    function _beginActivation(verb) {
        _activationVerb = verb
        _activationInFlight = true
        _activationEpoch += 1
        // Restart the watchdog timer for this fresh activation;
        // restart() handles the running-state transition idempotently
        // (Qt source: qqmltimer.cpp restart() = setRunning(false);
        // setRunning(true)). No prior explicit stop() is needed.
        activationWatchdog.restart()
        return _activationEpoch
    }
    function _endActivation() {
        if (!_activationInFlight) return
        _activationInFlight = false
        _activationVerb = ""
        activationWatchdog.stop()
    }
    // Stale-callback guard: invoked at the head of every async callback
    // before it touches in-flight state. Returns true iff the callback
    // belongs to the CURRENT chain. A false return is the signal to
    // silently drop the callback — the chain it represents has been
    // superseded (watchdog fired + user dismissed + user re-tapped)
    // and acting on its terminal state would corrupt the current chain.
    function _isCurrentEpoch(epoch) {
        return epoch === _activationEpoch && _activationInFlight
    }

    function _isSameActivationEpoch(epoch) {
        return epoch === _activationEpoch
    }

    // Wrap an async callback so it is silently dropped when the captured
    // chain epoch is no longer current. This is the only sanctioned way to
    // gate a pre-_doActivate or mid-_doActivate callback against stale
    // replies from an abandoned Activate/Deactivate chain. Adding a new
    // async leg without _withEpoch lets a stale callback mutate the current
    // chain.
    //
    // Usage:
    //   var epoch = _beginActivation("Activating")
    //   asyncOp(_withEpoch(epoch, function(reply) {
    //       // body runs only if the chain is still current; the
    //       // captured epoch matches _activationEpoch and the flag is
    //       // still set.
    //   }))
    function _withEpoch(epoch, fn) {
        return function() {
            if (!builtin._isCurrentEpoch(epoch)) return
            fn.apply(null, arguments)
        }
    }

    // Shared format-filter walk used by BOTH the Re-Activate purge
    // path AND the Deactivate path. Removes every priority-0
    // android_camera/android_microphone input registered with
    // ffstream, sorted highest-num-first so each RemoveInput
    // targets a still-valid index (RemoveInput shifts later
    // entries' nums down via slices.Delete).
    //
    // Keep this helper at top-level component scope so both Activate and
    // Deactivate can reach it. Nesting it inside either Button would make
    // the sibling flow fail with a QML ReferenceError and leave the watchdog
    // as the only path that clears the spinner.
    //
    // Callback contract:
    //   onAllDone(failureCount): invoked exactly once after every
    //     RemoveInput attempt completed (success OR failure). The
    //     failureCount lets callers surface a visible warning
    //     (Deactivate) or silently absorb (Re-Activate, where the
    //     subsequent AddInput leg is the actual error surface).
    //   onEnumerateError(err): invoked if the initial
    //     getInputsInfo call itself failed. Callers decide whether
    //     to bail or fall through to a controller-only path.
    //
    // Loop semantics: removeNext continues forward on individual
    // RemoveInput failures (a stale-num error must not strand the
    // user — UI state still needs to reach Inactive on Deactivate,
    // or land on AddInput on Re-Activate). We tally failures so
    // callers can decide whether to surface them.
    //
    // Concurrency notes:
    //   - callers MUST bumpUserIntentEpoch BEFORE invoking this helper
    //     if they will later call settingsController.activate() /
    //     deactivate(). Otherwise an in-flight reconcile reply landing
    //     mid-walk could observe a partially-purged priority-0 set and
    //     clobber m_active. This helper does not bump the epoch itself
    //     because the right moment to bump is at the user's tap
    //     (synchronously on the UI thread), not after we've already
    //     discovered the targets.
    //   - every async callback and remove dispatch is guarded by the
    //     activation epoch captured at helper entry. A timed-out purge
    //     may finish cleanup while no newer chain exists, but once the
    //     user retries and _beginActivation bumps the epoch, stale
    //     callbacks must not remove inputs belonging to the newer chain.
    function _removeBuiltinInputsAtPriority0(ffstreamClient, onAllDone, onEnumerateError) {
        var epoch = builtin._activationEpoch
        ffstreamClient.getInputsInfo(
            function(reply) {
                if (!builtin._isSameActivationEpoch(epoch)) return
                var targets = []
                // QtProtobuf exposes repeated fields via QML as
                // `<field>Data` (the C++ Q_PROPERTY uses the
                // `inputsData` name; `inputs` is only the C++
                // accessor). Fall back to `inputs` for
                // robustness against future codegen changes.
                var inputs = reply.inputsData || reply.inputs || []
                for (var i = 0; i < inputs.length; ++i) {
                    var inp = inputs[i]
                    if ((inp.priority || 0) !== 0) {
                        continue
                    }
                    var opts = []
                    if (inp.inputConfig) {
                        opts = inp.inputConfig.customOptionsData
                            || inp.inputConfig.customOptions
                            || []
                    }
                    var fmt = ""
                    for (var j = 0; j < opts.length; ++j) {
                        if (opts[j].key === "f") {
                            fmt = opts[j].value
                            break
                        }
                    }
                    if (fmt === "android_camera" || fmt === "android_microphone") {
                        targets.push(Number(inp.num || 0))
                    }
                }
                // Highest num first so each RemoveInput leaves
                // earlier nums valid. ffstream's RemoveInput does
                // slices.Delete on InputsInfo[priority], which
                // shifts later entries' nums down.
                targets.sort(function(a, b) { return b - a })
                var failureCount = 0
                function removeNext(idx) {
                    if (!builtin._isSameActivationEpoch(epoch)) return
                    if (idx >= targets.length) {
                        onAllDone(failureCount)
                        return
                    }
                    ffstreamClient.removeInput(0, targets[idx],
                        function(_) {
                            if (!builtin._isSameActivationEpoch(epoch)) return
                            removeNext(idx + 1)
                        },
                        function(err) {
                            if (!builtin._isSameActivationEpoch(epoch)) return
                            ffstreamClient.processGRPCError(err)
                            failureCount += 1
                            // Continue forward: a stale-num error
                            // must not leave the caller stuck —
                            // the UI / next leg still needs to
                            // make progress.
                            removeNext(idx + 1)
                        },
                        builtin.root.grpcCallOptions)
                }
                removeNext(0)
            },
            function(err) {
                if (!builtin._isSameActivationEpoch(epoch)) return
                // Caller handles: Re-Activate falls through to
                // _doActivate (best-effort); Deactivate falls
                // through to controller-only deactivate.
                onEnumerateError(err)
            },
            builtin.root.grpcCallOptions)
    }

    // Backwards-compatible thin wrapper for the Re-Activate purge
    // call site. Discards the failureCount because the subsequent
    // AddInput leg is the actual error surface for Activate flow.
    function _purgeBuiltinInputs(ffstreamClient, done) {
        _removeBuiltinInputsAtPriority0(ffstreamClient,
            function(_failureCount) { done() },
            function(err) {
                ffstreamClient.processGRPCError(err)
                // Best-effort: continue with activation even if
                // we couldn't enumerate; AddInput is still safe.
                done()
            })
    }

    function _enforceMissionCameraVideoCodec() {
        if (!settingsController) return ""
        if (settingsController
                && settingsController.videoCodec !== settingsController.missionVideoCodec) {
            console.warn("CamerasBuiltin: resetting camera videoCodec from",
                         settingsController.videoCodec,
                         "to", settingsController.missionVideoCodec)
            settingsController.videoCodec = settingsController.missionVideoCodec
        }
        return settingsController.missionVideoCodec
    }

    // _doActivate and _rollbackPriority0 live at top-level component
    // scope so Activate, Deactivate, rollback, and test paths all call the
    // same helpers. Re-inlining either helper inside a Button scope would
    // make sibling flows depend on a private QML scope and break the
    // two-daemon camera lifecycle.
    //
    // Camera-daemon contract: addInput / setOutputUrl / switchOutput target
    // ffstreamCameraClient (port 3594). The mediamtx-side ffstreamClient
    // (port 3593) is untouched by this path.
    function _doActivate(daemonAlreadyReady) {
        if (!builtin.root || !builtin.root.ffstreamCameraClient) {
            // No RPC channel — fall back to legacy file-only activation
            // so desktop/test harnesses without ffstream still work.
            // Synchronous terminal path: clear in-flight before the
            // watchdog has anything to do.
            settingsController.activate()
            builtin._endActivation()
            return
        }
        if (!daemonAlreadyReady) {
            var startEpoch = builtin._activationEpoch
            builtin._ensureFFStreamCameraDaemonReady(startEpoch, function() {
                builtin._doActivate(true)
            })
            return
        }
        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        // Capture the chain epoch once at dispatch. Every async
        // callback below routes through _withEpoch so a stale leg
        // from a superseded chain cannot end the new in-flight cue
        // or open a misleading dialog.
        var epoch = builtin._activationEpoch

        // Configuration-error empty-URL guard (Task #124, F-task116-3
        // Pool C). builtinCameraPublisherUrl() resolves the user-configured
        // outputUrl through the publisher template; an empty string here
        // means the user has not configured the destination yet. Pre-fix
        // behaviour: the chain registered the camera + microphone inputs,
        // then setOutputUrl("") was rejected by the avd publisher regex
        // mid-chain, leaving Wing Out with phantom inputs registered
        // against no output URL. The guard short-circuits the chain at the
        // earliest point that the URL is observable, opens the existing
        // activateErrorDialog with a "Output URL" leg label so the user
        // can act, and clears the in-flight cue so the user is not
        // stranded with a permanent "Activating…" label.
        var publisherUrl = builtin.root.builtinCameraPublisherUrl()
        if (!publisherUrl || String(publisherUrl).length === 0) {
            builtin._showActivateConfigurationError(
                "Output URL",
                "Enter a valid output URL before activating the built-in "
                + "camera.")
            return
        }

        var cameraVideoCodec = builtin._enforceMissionCameraVideoCodec()
        var camIndex = builtin.cameraIndexForPreferredCamera(
            settingsController.preferredCamera)
        var camIndexStr = String(camIndex)
        var camCustomOpts = [
            { key: "f",            value: "android_camera" },
            { key: "camera_index", value: camIndexStr },
            { key: "pixel_format", value: "yuv420p" },
            { key: "video_size",   value: settingsController.width + "x" + settingsController.height },
            { key: "framerate",    value: String(settingsController.fps) }
        ]
        // Camera URL: the demuxer URL is the camera id ("0" back, "1" front),
        // mirrored from camera_index for the Android camera demuxer.
        ffstreamCameraClient.addInput(0, camIndexStr, camCustomOpts,
            builtin._withEpoch(epoch, function(camReply) {
                var camNum = camReply.num
                // Mic leg: empty URL + mission sample_rate=48000.
                var micCustomOpts = [
                    { key: "f",           value: "android_microphone" },
                    { key: "sample_rate", value: "48000" }
                ]
                ffstreamCameraClient.addInput(0, "", micCustomOpts,
                    builtin._withEpoch(epoch, function(micReply) {
                        var micNum = micReply.num
                        // Leg 3: SetOutputURL — push the AVD
                        // PUBLISHER URL (port 1946 + template
                        // tokens) to the daemon. NOT the user's
                        // settingsController.outputUrl, which is the
                        // CONSUMER URL (port 1945 / "<stem>-merged")
                        // and would be rejected by avd's publisher
                        // regex, wedging the libav RTMP open inside
                        // avpipeline/kernel/output.go's
                        // astiav.OpenIOContext call. See
                        // Main.qml:builtinCameraPublisherUrl().
                        var outputUrl = builtin.root.builtinCameraPublisherUrl()
                        ffstreamCameraClient.setOutputUrl(outputUrl,
                            builtin._withEpoch(epoch, function(_) {
                                // Leg 4: SwitchOutputByProps — apply
                                // mission AV1 plus the camera resolution
                                // and bitrate settings.
                                ffstreamCameraClient.switchOutput(
                                    cameraVideoCodec,
                                    settingsController.width,
                                    settingsController.height,
                                    settingsController.bitrateKbps * 1000,
                                    settingsController.audioCodec,
                                    settingsController.audioSampleRate,
                                    settingsController.audioBitrateKbps * settingsController.audioChannels * 1000,
                                    settingsController.maxBitrateKbps * 1000,
                                    builtin._withEpoch(epoch, function(_2) {
                                        // All four legs succeeded — commit intent
                                        // and end the in-flight cue. Order: commit
                                        // first so the status label sees Active
                                        // when _endActivation flips _activationInFlight
                                        // false (otherwise there is a one-frame
                                        // window where the label reads Inactive).
                                        settingsController.activeCameraNum = camNum
                                        settingsController.activeMicrophoneNum = micNum
                                        settingsController.activate()
                                        builtin._endActivation()
                                    }),
                                    builtin._withEpoch(epoch, function(err) {
                                        builtin._rollbackPriority0(ffstreamCameraClient)
                                        builtin._showActivateError("SwitchOutputByProps", err)
                                    }),
                                    builtin.root.grpcCallOptions)
                            }),
                            builtin._withEpoch(epoch, function(err) {
                                builtin._rollbackPriority0(ffstreamCameraClient)
                                builtin._showActivateError("Output URL", err)
                            }),
                            builtin.root.grpcCallOptions)
                    }),
                    builtin._withEpoch(epoch, function(err) {
                        // Mic-leg failed: roll back via shared helper
                        // (bumps epoch + removes every priority-0
                        // android_camera/android_microphone).
                        builtin._rollbackPriority0(ffstreamCameraClient)
                        builtin._showActivateError("Microphone input", err)
                    }),
                    builtin.root.grpcCallOptions)
            }),
            builtin._withEpoch(epoch, function(err) {
                // Camera leg failed before any state changed; just surface.
                builtin._showActivateError("Camera input", err)
            }),
            builtin.root.grpcCallOptions)
    }

    // Shared rollback helper: bumps userIntentEpoch first (so any
    // in-flight reconcile reply is dropped) then walks the
    // priority-0 android_camera/android_microphone set on the
    // camera daemon and removes them. Used by every leg of the
    // _doActivate chain past the camera-AddInput.
    //
    // Idempotent under repeat calls: a second invocation re-runs
    // _removeBuiltinInputsAtPriority0 which finds zero targets
    // (the first call already cleared them) and tail-calls its
    // onAllDone(0) with no further RPCs.
    //
    // Hoisted to top-level scope alongside _doActivate so any caller
    // reaches the same rollback definition.
    function _rollbackPriority0(ffstreamCameraClient) {
        if (settingsController) {
            settingsController.bumpUserIntentEpoch()
        }
        _removeBuiltinInputsAtPriority0(ffstreamCameraClient,
            function(_failureCount) { /* swallow — surfaced by activate dialog */ },
            function(rbErr) { ffstreamCameraClient.processGRPCError(rbErr) })
    }

    // gRPC code 1 = Cancelled, 14 = Unavailable. processGRPCError
    // already swallows these (ffstream_client.cpp:72-81); they
    // represent transient channel churn, not "operation failed".
    // Mirror that filter so the dialog doesn't fire on a benign reconnect.
    function _isUserVisibleGrpcError(err) {
        if (!err) return false
        var c = (err.code !== undefined) ? Number(err.code) : -1
        if (c === 1 || c === 14) return false
        return true
    }

    function _formatGrpcError(err) {
        if (!err) return "Unknown error."
        var msg = (err.message && String(err.message).length > 0)
                  ? String(err.message)
                  : "(no error message)"
        var code = (err.code !== undefined) ? Number(err.code) : -1
        return "gRPC code " + code + ": " + msg
    }

    function _showActivateError(legLabel, err) {
        // Terminal error path on the Activate chain: the in-flight flag
        // must clear regardless of whether the error is user-visible.
        // gRPC Cancelled / Unavailable still END the chain (we abort
        // the leg sequence and roll back); we just suppress the visible
        // dialog so the existing reconnect path can churn quietly. If
        // we left the flag set on those codes, the spinner would spin
        // until the watchdog fired even though the chain is already
        // dead.
        builtin._endActivation()
        // Route through the camera client: AddInput / SetOutputURL /
        // SwitchOutputByProps target ffstreamCameraClient. Pushing the
        // error into THAT client's processGRPCError keeps its reconnect /
        // channel-recreate path alive on Internal/Unavailable codes.
        if (builtin.root && builtin.root.ffstreamCameraClient) {
            builtin.root.ffstreamCameraClient.processGRPCError(err)
        }
        if (!_isUserVisibleGrpcError(err)) return
        activateErrorDialog.leg = legLabel
        activateErrorDialog.detail = _formatGrpcError(err)
        activateErrorDialog.open()
    }

    function _inputInfoIsBuiltinCapture(inp) {
        if (!inp || (inp.priority || 0) !== 0) {
            return false
        }
        var opts = []
        if (inp.inputConfig) {
            opts = inp.inputConfig.customOptionsData
                || inp.inputConfig.customOptions
                || []
        }
        for (var i = 0; i < opts.length; ++i) {
            if (opts[i].key !== "f") {
                continue
            }
            return opts[i].value === "android_camera"
                || opts[i].value === "android_microphone"
        }
        return false
    }

    function _replyHasBuiltinCaptureInputs(reply) {
        var inputs = reply && (reply.inputsData || reply.inputs || [])
        for (var i = 0; i < inputs.length; ++i) {
            if (builtin._inputInfoIsBuiltinCapture(inputs[i])) {
                return true
            }
        }
        return false
    }

    function _isGrpcCancelledOrUnavailable(err) {
        if (!err) {
            return false
        }
        var c = (err.code !== undefined) ? Number(err.code) : -1
        return c === 1 || c === 14
    }

    function _commitDeactivate() {
        settingsController.activeCameraNum = -1
        settingsController.activeMicrophoneNum = -1
        settingsController.deactivate()
        builtin._ffstreamCameraDaemonKnownStopped = true
        builtin._endActivation()
    }

    function _scheduleDeactivateIdleProbe(epoch, attemptsLeft) {
        if (attemptsLeft <= 0) {
            builtin._showDeactivateError(
                "ffstream-camera still reports built-in camera or "
                + "microphone inputs after End.")
            builtin._endActivation()
            return
        }
        builtin._ffstreamCameraDeactivateIdleEpoch = epoch
        builtin._ffstreamCameraDeactivateIdleAttemptsLeft = attemptsLeft
        ffstreamCameraDeactivateIdleProbeTimer.restart()
    }

    function _probeDeactivateIdle(epoch, attemptsLeft) {
        if (!builtin._isCurrentEpoch(epoch)) return
        if (!builtin.root || !builtin.root.ffstreamCameraClient) {
            builtin._commitDeactivate()
            return
        }
        if (attemptsLeft <= 0) {
            builtin._scheduleDeactivateIdleProbe(epoch, 0)
            return
        }

        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        ffstreamCameraClient.getInputsInfo(
            builtin._withEpoch(epoch, function(reply) {
                if (!builtin._replyHasBuiltinCaptureInputs(reply)) {
                    builtin._commitDeactivate()
                    return
                }
                if (attemptsLeft <= 1) {
                    builtin._scheduleDeactivateIdleProbe(epoch, 0)
                    return
                }
                builtin._scheduleDeactivateIdleProbe(epoch, attemptsLeft - 1)
            }),
            builtin._withEpoch(epoch, function(err) {
                if (typeof ffstreamCameraClient.processGRPCError === "function") {
                    ffstreamCameraClient.processGRPCError(err)
                }
                if (builtin._isGrpcCancelledOrUnavailable(err)) {
                    builtin._commitDeactivate()
                    return
                }
                builtin._showDeactivateError(builtin._formatGrpcError(err))
                builtin._endActivation()
            }),
            builtin._ffstreamCameraStartupProbeOptions())
    }

    // Deactivate's primary teardown is the dedicated ffstream-camera
    // daemon's End RPC. Do not remove inputs here: Activate rollback and
    // Re-Activate purge still use RemoveInput. End returns before server
    // shutdown is necessarily visible to clients, so a successful End reply
    // is followed by a readiness probe: inactive is committed only when the
    // old daemon disappears or a supervisor-relaunched daemon reports no
    // built-in camera/mic inputs.
    function _doDeactivate() {
        var epoch = builtin._beginActivation("Deactivating")

        if (settingsController) {
            settingsController.bumpUserIntentEpoch()
        }
        if (!builtin.root || !builtin.root.ffstreamCameraClient) {
            builtin._commitDeactivate()
            return
        }

        var ffstreamCameraClient = builtin.root.ffstreamCameraClient
        ffstreamCameraClient.end(
            builtin._withEpoch(epoch, function(_) {
                builtin._probeDeactivateIdle(
                    epoch,
                    builtin.ffstreamCameraStartupProbeAttempts)
            }),
            builtin._withEpoch(epoch, function(err) {
                ffstreamCameraClient.processGRPCError(err)
                builtin._showDeactivateError(builtin._formatGrpcError(err))
                builtin._endActivation()
            }),
            builtin.root.grpcCallOptions)
    }

    // root must be non-null; standalone instantiation is unsupported (the
    // panel binds to root.streamingSettings for single-source-of-truth).
    // Declared `required` so the QML engine fails at component load with a
    // clear error if a caller forgets to pass it, instead of every binding
    // below crashing with "TypeError: Cannot read property X of null" the
    // moment it tries to evaluate settingsController.active. Cameras.qml is
    // the only instantiation site and already passes camerasPage.root.
    required property var root

    // Bind to the root-owned controller (Main.qml:138) so that the
    // status label, Activate/Deactivate buttons, and the Settings page
    // all reflect a single source of truth. A previously-local instance
    // here desynced from Main's m_active: ffstream-driven reconciliation
    // would update root's instance but leave this one lying.
    //
    // No null-guard: builtin.root is `required`, so QML guarantees it is
    // non-null at component load.
    readonly property var settingsController: builtin.root.streamingSettings

    // Status row. While an Activate / Deactivate chain is in flight the
    // label switches to the present-continuous form ("Activating…" /
    // "Deactivating…") and a small BusyIndicator is shown alongside it
    // so the user has visible confirmation that their tap registered
    // within one frame — see _activationInFlight comment for the bug
    // this prevents.
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: builtin._activationInFlight
                  ? ("Status: " + builtin._activationVerb + "…")
                  : (settingsController.active ? "Status: Active" : "Status: Inactive")
            color: "#ffffff"
            font.pointSize: 16
            Layout.alignment: Qt.AlignVCenter
        }

        // Inline progress cue. Sized to the label's typographic height so
        // it sits flush with the text rather than dwarfing it. `visible`
        // (rather than opacity) keeps the row from reserving space when
        // idle, so the layout doesn't shift on each tap.
        BusyIndicator {
            id: activationBusyIndicator
            running: builtin._activationInFlight
            visible: builtin._activationInFlight
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
        }
    }

    // Scrollable settings section: every camera + codec setting lives in
    // a ScrollView so the user can reach all fields on a small screen.
    // The Activate/Deactivate row (below the ScrollView) is the only
    // pinned section; it stays visible regardless of scroll position so
    // the primary action is always one tap away.
    //
    // Output URL + Apply are the LAST item in the inner ColumnLayout
    // (natural reading order: Status → camera/codec settings → output
    // URL → Apply). Tapping Output URL raises the on-screen keyboard;
    // the field stays visible because:
    //   1) AndroidManifest sets windowSoftInputMode=adjustResize, so the
    //      Android window resizes for the IME — the ScrollView's height
    //      shrinks naturally.
    //   2) settingsScroll.scrollOutputUrlIntoView() runs on
    //      outputUrlField's onActiveFocusChanged, programmatically
    //      setting Flickable.contentY so the field's bottom edge sits
    //      just above the keyboard. The previous attempt (5b9ac19) hit a
    //      Qt 6 Flickable.contentHeight underflow on Pixel 8a — the
    //      auto-calc capped at the second-to-last child's bottom rather
    //      than the last (the bottom Layout.bottomMargin wasn't included).
    //      Fix: explicitly assign contentHeight from the
    //      ColumnLayout's implicitHeight before computing the scroll
    //      target.
    ScrollView {
        id: settingsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth

        // Smallest Flickable viewport height observed while the IME
        // was visible. The second-tap regression (#15 exact repro) is
        // fixed by pinning effective viewport to this value when the
        // keyboard is still up but Flickable's height has bounced
        // back to pre-keyboard size (Android occasionally hands us an
        // overlay window-mode flip with no Qt.inputMethod hide signal
        // — see scrollOutputUrlIntoView for the full root-cause
        // writeup). Reset to 0 when the keyboard hides or the field
        // loses focus, so we don't carry a stale floor into the next
        // edit session. Unit-agnostic: works in whatever coord system
        // Flickable.height reports, unlike a direct comparison
        // against Qt.inputMethod.keyboardRectangle (which on Android
        // Qt 6.10 reports in NATIVE pixels while Flickable.height is
        // in logical pixels — confirmed empirically).
        property real shrunkenViewportFloor: 0

        // Pure helper exported for unit testing — given the inputs
        // that govern scroll target placement, returns the contentY
        // value that scrollOutputUrlIntoView would assign. Extracting
        // this into a side-effect-free function lets the QML test
        // (tst_cameras_builtin_scroll_target.qml) drive the math
        // directly without standing up a real Flickable / IME, and
        // catches the floor-clamping regression that would otherwise
        // require a real Android keyboard to reproduce.
        function _computeScrollTarget(flHeight, contentHeight,
                                       fieldBottom, pad,
                                       imVisible, floor) {
            var effectiveH = flHeight
            if (imVisible && floor > 0 && floor < effectiveH) {
                effectiveH = floor
            }
            var maxScroll = Math.max(0, contentHeight - effectiveH)
            var target = Math.max(0, fieldBottom + pad - effectiveH)
            return Math.min(maxScroll, target)
        }

        function scrollOutputUrlIntoView() {
            var fl = settingsScroll.contentItem
            if (!fl || fl.contentY === undefined) return
            // Force-reconcile contentHeight against the ColumnLayout's
            // actual implicitHeight: ScrollView's auto-calculation
            // sometimes underflows the bottom margin in Qt 6.10 on Pixel
            // 8a, capping maxScroll short of the last field by ~50px.
            // Reading settingsColumn.implicitHeight + a small pad gives
            // the Flickable enough room to scroll the field into view.
            if (settingsColumn) {
                fl.contentHeight = settingsColumn.implicitHeight + 24
            }
            var pt = outputUrlField.mapToItem(fl.contentItem || fl, 0, 0)
            var fieldBottom = pt.y + outputUrlField.height
            var pad = 20

            // Effective visible viewport height. Normally this equals
            // fl.height — when Android resizes the window for the IME
            // (windowSoftInputMode=adjustResize), the Flickable shrinks
            // and fl.height already reflects the keyboard's occupation.
            //
            // BUG REGRESSION on the SECOND consecutive tap onto an
            // already-focused TextField (#15 exact repro):
            //
            //   tap-1 → activeFocusChanged + IME show + adjustResize
            //           → fl.height shrinks (424 logical on Pixel 8a)
            //   tap-2 → cursorPositionChanged + IME requests show again
            //           → Android restores the window to full size
            //             (fl.height jumps back to 703) WHILE the
            //             keyboard is still drawn on top. No
            //             keyboardRectangleChanged or visibleChanged
            //             fires (the IME never went away). The only
            //             signal we get is contentItem.heightChanged
            //             back to 703.
            //   handler → scrollOutputUrlIntoView with fl.height=703
            //             computes target=169 — geometrically correct
            //             for a full 703-tall viewport, but the bottom
            //             279 logical is occluded by the keyboard.
            //             Field bottom (683 from fl-top) is below the
            //             true visible bound (~424 from fl-top).
            //             FIELD HIDDEN.
            //
            // Defense: when the keyboard is still visible, clamp
            // effectiveH to the smallest fl.height we observed during
            // this edit session (shrunkenViewportFloor, captured by
            // the contentItem.heightChanged handler when IME is
            // visible). The first heightChanged after IME show
            // captures the true post-resize value (424 above); a
            // later bounce back to 703 doesn't lift the floor.
            // Reset on visible→false (IME hide) so the floor doesn't
            // poison the next edit session.
            //
            // Test mirror: tst_cameras_builtin_scroll_target.qml
            // exercises _computeScrollTarget with the exact phone
            // values (flH=703 floor=424 fb=852 pad=20 imVisible=true
            // → target=448, NOT 169) and the falsifier path
            // (floor=0 → target=169 demonstrating the bug returns
            // when the floor is bypassed).
            fl.contentY = settingsScroll._computeScrollTarget(
                fl.height, fl.contentHeight, fieldBottom, pad,
                Qt.inputMethod.visible,
                settingsScroll.shrunkenViewportFloor)
        }

        // Re-trigger the scroll-into-view whenever the viewport height
        // changes WHILE outputUrlField has focus — covers the Android
        // adjustResize transition (window shrinks as the IME animates
        // in; the first onActiveFocusChanged scroll runs against the
        // pre-shrink height and undershoots).
        Connections {
            target: settingsScroll.contentItem
            function onHeightChanged() {
                var h = settingsScroll.contentItem.height
                // While the IME is visible AND the field has focus,
                // any new fl.height that's SMALLER than the current
                // floor is the "real" post-keyboard viewport. We
                // never raise the floor — only lower it — so the
                // second-tap window-mode-flip (which bounces height
                // back UP without an IME hide) doesn't poison the
                // scroll math. See scrollOutputUrlIntoView for the
                // full root-cause writeup.
                if (Qt.inputMethod.visible && h > 0
                        && outputUrlField && outputUrlField.activeFocus) {
                    if (settingsScroll.shrunkenViewportFloor === 0
                            || h < settingsScroll.shrunkenViewportFloor) {
                        settingsScroll.shrunkenViewportFloor = h
                    }
                }
                if (outputUrlField && outputUrlField.activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                }
            }
        }

        // Re-trigger the scroll-into-view on every IME state change
        // while outputUrlField has focus. The previous focus-changed
        // handler alone fires only on the initial tap; if the user
        // long-presses the cursor handle and drags it, the IME emits
        // cursorRectangleChanged but NOT activeFocusChanged, so the
        // scroll didn't re-evaluate and the field could slide back
        // under the keyboard. AnchorRectangle covers selection
        // expansion (toolbar appearance changes the IME rect height);
        // keyboardRectangle covers IME show/hide-and-reshow during
        // drag; visible covers the soft-keyboard transient hide. Each
        // handler is no-op'd when the field doesn't have focus, so
        // taps on other input-bearing controls (none on this tab
        // today, but defensively) won't trigger spurious scrolls.
        Connections {
            target: Qt.inputMethod
            function onCursorRectangleChanged() {
                if (outputUrlField && outputUrlField.activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                }
            }
            function onAnchorRectangleChanged() {
                if (outputUrlField && outputUrlField.activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                }
            }
            function onKeyboardRectangleChanged() {
                if (outputUrlField && outputUrlField.activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                }
            }
            function onVisibleChanged() {
                if (!Qt.inputMethod.visible) {
                    // IME hidden — drop the floor so the next edit
                    // session starts from a clean slate.
                    settingsScroll.shrunkenViewportFloor = 0
                }
                if (outputUrlField && outputUrlField.activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                }
            }
        }

        ColumnLayout {
            id: settingsColumn
            width: parent.width
            spacing: 8

    RowLayout {
        Layout.fillWidth: true

        SpinBox {
            id: widthSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 160
            to: 3840
            stepSize: 16

            value: settingsController.width
            onValueModified: settingsController.width = value

            textFromValue: function (v) {
                return v + " px";
            }
        }

        Label {
            text: "x"
            color: "#ffffff"
            font.pointSize: 20
        }

        SpinBox {
            id: heightSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 120
            to: 2160
            stepSize: 16

            value: settingsController.height
            onValueModified: settingsController.height = value

            textFromValue: function (v) {
                return v + " px";
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "FPS"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: fpsSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 5
            to: 60
            value: settingsController.fps

            onValueModified: settingsController.fps = value
            stepSize: 1
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Bitrate (Kbps)"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: bitrateSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 256
            to: 20000
            value: settingsController.bitrateKbps

            onValueModified: settingsController.bitrateKbps = value
            stepSize: 256
        }
    }

    // Max bitrate is sent with the video switchOutput request. Keep it with
    // the video block; backend propagation beyond SwitchOutputByPropsRequest
    // is owned by ffstream/avpipeline.
    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Max bitrate (Kbps)"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: maxBitrateSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 1000
            to: 100000
            stepSize: 500
            value: settingsController.maxBitrateKbps
            onValueModified: settingsController.maxBitrateKbps = value
        }
    }

    // Video codec selection (was Settings -> Codec tab pre-consolidation).
    // Mission camera streaming exposes one live codec: the controller's
    // canonical AV1 MediaCodec encoder.
    ListModel {
        id: codecModel
    }

    function rebuildCodecModel() {
        var missionCodec = builtin._enforceMissionCameraVideoCodec()
        var prevValue = codecCombo.currentIndex >= 0 && codecCombo.currentIndex < codecModel.count
            ? codecModel.get(codecCombo.currentIndex).value
            : missionCodec
        codecModel.clear()
        codecModel.append({ name: "AV1 (HW)", value: missionCodec, hardware: true })
        var newIdx = 0
        for (var i = 0; i < codecModel.count; i++) {
            if (codecModel.get(i).value === prevValue) {
                newIdx = i
                break
            }
        }
        if (newIdx === 0 && codecModel.get(0).value !== prevValue) {
            // The previously selected codec is no longer offered. Surface the
            // reset via codecResetNotice so the change is auditable in logs and
            // the UI.
            console.warn("rebuildCodecModel: previously selected codec '"
                + prevValue + "' is no longer offered; "
                + "falling back to '" + codecModel.get(0).value + "'")
            builtin.codecResetNotice = qsTr("Codec was reset to %1 because the previous selection is no longer available.")
                .arg(codecModel.get(0).name)
            settingsController.videoCodec = codecModel.get(0).value
        } else {
            builtin.codecResetNotice = ""
        }
        codecCombo.currentIndex = newIdx
    }

    Component.onCompleted: rebuildCodecModel()

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Video codec"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: codecCombo
            Layout.fillWidth: true
            font.pointSize: 16
            textRole: "name"
            valueRole: "value"
            model: codecModel
            onActivated: function(idx) {
                if (idx < 0 || idx >= codecModel.count) return
                settingsController.videoCodec = codecModel.get(idx).value
            }
        }
    }

    Label {
        visible: builtin.codecResetNotice !== ""
        text: builtin.codecResetNotice
        color: "#a06000"
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    // Preferred camera lives in the video block: which physical camera
    // (Front / Back) feeds the video encoder.
    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Preferred camera"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: cameraCombo
            Layout.fillWidth: true
            font.pointSize: 20
            model: ["Front", "Back"]

            // Synchronize with controller
            Component.onCompleted: {
                currentIndex = settingsController.preferredCamera === "Back" ? 1 : 0
            }

            onActivated: function(index) {
                settingsController.preferredCamera = (index === 1) ? "Back" : "Front"
            }

            // Also handle external changes (e.g. loaded from file)
            Connections {
                target: settingsController
                function onPreferredCameraChanged() {
                    cameraCombo.currentIndex =
                        settingsController.preferredCamera === "Back" ? 1 : 0
                }
            }
        }
    }

    // Microphone — first field of the audio block. Picks which physical
    // mic input feeds the audio encoder.
    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Microphone"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: micCombo
            Layout.fillWidth: true
            font.pointSize: 20
            textRole: "displayLabel"
            valueRole: "id"
            model: builtin.root && builtin.root.microphoneController
                   ? builtin.root.microphoneController.devices
                   : []

            // Sync from settingsController on first show / model refresh.
            function syncFromController() {
                if (!model || model.length === 0) {
                    return;
                }
                for (var i = 0; i < model.length; ++i) {
                    if (model[i].id === settingsController.preferredMicrophoneId) {
                        currentIndex = i;
                        return;
                    }
                }
                currentIndex = 0;
            }

            onModelChanged: syncFromController()
            Component.onCompleted: syncFromController()

            onActivated: function(index) {
                if (index < 0 || index >= model.length) {
                    return;
                }
                settingsController.preferredMicrophoneId = model[index].id
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Audio codec"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: audioCodecCombo
            Layout.fillWidth: true
            font.pointSize: 16
            textRole: "name"
            valueRole: "value"
            model: ListModel {
                id: audioCodecModel
                ListElement { name: "AAC";  value: "aac" }
                ListElement { name: "Opus"; value: "opus" }
            }
            Component.onCompleted: {
                for (var i = 0; i < audioCodecModel.count; i++) {
                    if (audioCodecModel.get(i).value === settingsController.audioCodec) {
                        currentIndex = i
                        break
                    }
                }
            }
            onActivated: function(idx) {
                settingsController.audioCodec = audioCodecModel.get(idx).value
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Audio sample rate (Hz)"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        ComboBox {
            id: audioRateCombo
            Layout.fillWidth: true
            font.pointSize: 16
            model: [16000, 24000, 44100, 48000]
            Component.onCompleted: {
                for (var i = 0; i < model.length; i++) {
                    if (model[i] === settingsController.audioSampleRate) {
                        currentIndex = i
                        break
                    }
                }
            }
            onActivated: function(idx) {
                settingsController.audioSampleRate = model[idx]
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Audio bitrate (Kbps/ch)"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: audioBitrateSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 32
            to: 256
            stepSize: 8
            value: settingsController.audioBitrateKbps
            onValueModified: settingsController.audioBitrateKbps = value
        }
    }

    RowLayout {
        Layout.fillWidth: true

        Label {
            text: "Audio channels"
            color: "#ffffff"
            font.pointSize: 20
            Layout.alignment: Qt.AlignVCenter
        }

        SpinBox {
            id: audioChannelsSpin
            Layout.fillWidth: true
            font.pointSize: 20
            from: 1
            to: 2
            stepSize: 1
            value: settingsController.audioChannels
            onValueModified: settingsController.audioChannels = value
        }
    }

    // Output URL + Apply — the LAST scrollable items, in natural reading
    // order. Tapping outputUrlField raises the keyboard; the
    // onActiveFocusChanged handler programmatically scrolls the
    // ColumnLayout so the field stays visible above the IME (see
    // settingsScroll.scrollOutputUrlIntoView).
    GridLayout {
        columns: 2
        columnSpacing: 12
        rowSpacing: 8
        Layout.fillWidth: true
        Layout.topMargin: 8

        Label {
            text: "Output URL:"
            color: "#ffffff"
            font.pointSize: 16
        }
        TextField {
            id: outputUrlField
            Layout.fillWidth: true
            font.pointSize: 16
            text: settingsController.outputUrl
            placeholderText: "rtmp://host/app/stream  (empty = null/discard)"
            // URL semantics: ImhUrlCharactersOnly tells Android to surface
            // a URL-shaped on-screen keyboard layout, ImhNoPredictiveText
            // disables predictive / swipe-to-type which on Pixel 8a
            // intercepted cursor-handle drag gestures and silently
            // inserted characters (e.g. "${v:0:height}" → "${v:0:sheight}",
            // "${v:0:codec}" → "${v:0:}") into the persisted URL.
            // ImhNoAutoUppercase + ImhSensitiveData (no learned-text
            // suggestions) defend the same path: the IME
            // must not silently mutate the field's content under any
            // gesture. ImhPreferLowercase keeps the URL lowercase by
            // default since RTMP host/path is case-sensitive in some
            // server implementations.
            inputMethodHints: Qt.ImhUrlCharactersOnly
                              | Qt.ImhNoPredictiveText
                              | Qt.ImhNoAutoUppercase
                              | Qt.ImhSensitiveData
                              | Qt.ImhPreferLowercase
            // Persist on commit, NOT on every keystroke. The previous
            // onTextChanged handler called setOutputUrl(text.trim())
            // synchronously per character, which (with m_active=true)
            // wrote streaming_settings.json on every char — every
            // intermediate mid-edit string (including IME-induced
            // garbage like "${v:0:sheight}") landed on disk. On wingout
            // restart, the loader picked up whatever transient state
            // was persisted last, often producing the URL-mangling
            // pattern the user reported (#17). onEditingFinished fires
            // only when the field loses focus or Enter is pressed —
            // the natural commit boundary. Tapping Apply causes the
            // field to lose focus FIRST (button-click steals focus),
            // so onEditingFinished runs before Apply's onClicked reads
            // settingsController.outputUrl, preserving the existing
            // Apply-button semantics.
            onEditingFinished: settingsController.outputUrl = text.trim()
            // Scroll-into-view on focus so the on-screen keyboard does
            // not cover the field. Uses Qt.callLater to defer one event
            // loop tick — gives the IME's adjustResize transition a
            // chance to start, so the Flickable.height we read in the
            // scroll math is the post-shrink (not pre-shrink) value.
            // settingsScroll.contentItem.heightChanged will re-trigger
            // the scroll once the resize completes (see Connections in
            // settingsScroll above).
            onActiveFocusChanged: {
                if (activeFocus) {
                    Qt.callLater(settingsScroll.scrollOutputUrlIntoView)
                } else {
                    // Field defocused — reset the viewport-floor so
                    // a future edit session on this same field
                    // starts fresh (the next tap-1 → IME-show cycle
                    // re-captures the post-keyboard fl.height).
                    settingsScroll.shrunkenViewportFloor = 0
                }
            }
        }
    }

    Button {
        Layout.fillWidth: true
        text: "Apply"
        font.pointSize: 16
        highlighted: true
        Layout.bottomMargin: 8
        onClicked: {
            var cameraVideoCodec = builtin._enforceMissionCameraVideoCodec()
            // Persist current selections (writes streaming_settings.json
            // unconditionally via activate(); idempotent if active).
            settingsController.activate()
            if (!builtin.root || !builtin.root.ffstreamCameraClient) {
                console.warn("CamerasBuiltin: ffstreamCameraClient not available")
                return
            }
            console.log("CamerasBuiltin: applying codec",
                cameraVideoCodec,
                settingsController.width + "x" + settingsController.height,
                settingsController.bitrateKbps + "kbps",
                settingsController.audioCodec,
                settingsController.audioSampleRate + "Hz",
                settingsController.audioBitrateKbps + "kbps",
                "max=" + settingsController.maxBitrateKbps + "kbps")
            // Push the publisher URL (port 1946 + template tokens, NOT
            // the consumer port-1945 "<stem>-merged" form) so avd's
            // publisher regex accepts it. See builtinCameraPublisherUrl.
            var pubUrl = builtin.root.builtinCameraPublisherUrl()
            if (pubUrl.length > 0) {
                builtin.root.ffstreamCameraClient.setOutputUrl(pubUrl,
                    function(_) { console.log("CamerasBuiltin Apply: setOutputUrl ok") },
                    function(err) {
                        console.warn("CamerasBuiltin Apply: setOutputUrl failed")
                        builtin.root.ffstreamCameraClient.processGRPCError(err)
                    },
                    builtin.root.grpcCallOptions)
            }
            builtin.root.ffstreamCameraClient.switchOutput(
                cameraVideoCodec,
                settingsController.width,
                settingsController.height,
                settingsController.bitrateKbps * 1000,
                settingsController.audioCodec,
                settingsController.audioSampleRate,
                settingsController.audioBitrateKbps * settingsController.audioChannels * 1000,
                settingsController.maxBitrateKbps * 1000,
                function(_) { console.log("CamerasBuiltin Apply: switchOutput ok") },
                function(err) {
                    console.warn("CamerasBuiltin Apply: switchOutput failed")
                    builtin.root.ffstreamCameraClient.processGRPCError(err)
                },
                builtin.root.grpcCallOptions)
        }
    }

        } // ColumnLayout (inside ScrollView)
    } // ScrollView (closes the scrollable settings section)

    RowLayout {
        Layout.fillWidth: true

        Button {
            Layout.fillWidth: true
            font.pointSize: 20
            text: settingsController.active ? "Re-Activate" : "Activate"
            // Block re-entry while the previous Activate or Deactivate
            // chain is still in flight. The chain is multi-leg and
            // mutates ffstream registration state mid-run; a second tap
            // before the first completes would race the rollback paths
            // and corrupt the in-flight rebuild. The watchdog is the
            // backstop that re-enables this button if the chain
            // genuinely never completes.
            //
            // Also gated by _backendReachable (Task #124): the proactive
            // gRPC reachability monitor flips this flag false when the
            // ffstream-camera daemon stops responding for longer than
            // _grpcUnreachableGraceMs. Pre-fix behaviour: button stayed
            // enabled while the daemon was unreachable; tapping fired the
            // multi-leg gRPC chain into the void with no UI feedback
            // ("qt.grpc : No channel(s) attached" log flood, Task #116).
            // The Re-Activate label is still present because settingsController.active
            // can be true (input registry observed inputs) even while the
            // proactive probe is failing — the user must wait for the
            // daemon to recover before re-trying either path.
            enabled: !builtin._activationInFlight && builtin._backendReachable

            // Chain runtime permission requests before issuing the
            // addInput RPCs. The android_camera / android_microphone
            // demuxers won't open without the platform permissions, so we
            // must request CAMERA, then RECORD_AUDIO, then call addInput
            // only on the all-granted path. On either denial we surface
            // permDeniedDialog and bail.
            //
            // Helpers _removeBuiltinInputsAtPriority0, _purgeBuiltinInputs,
            // _doActivate, and _rollbackPriority0 all live at top-level
            // `builtin` scope — see the SCOPE INVARIANT block at the top
            // of the file. Re-inlining any of them inside this Button's
            // QML scope makes sibling buttons unable to reach the helpers.

            // Manual device checks for lifecycle pieces outside the headless
            // QML harness:
            //  - Tap Activate with ffstream-camera stopped -> Wing Out only
            //    probes the rc.local-owned daemon; it does not start Ubuntu,
            //    invoke su/chroot, or launch the supervisor loop. If the
            //    probe budget expires, the stopped-daemon dialog opens and
            //    the button is retryable.
            //  - Tap Activate with the camera daemon up but reachability
            //    broken at the SetOutputURL leg -> camera + mic legs
            //    succeed, output-URL leg fails, both inputs are rolled
            //    back, dialog fires "Output URL", status stays Inactive.
            //  - Tap Activate with the daemon up and reachable -> 4-leg
            //    chain (AddInput camera + AddInput mic + SetOutputURL +
            //    SwitchOutputByProps) all succeed, status flips Active.

            onClicked: {
                // Visible cue first, synchronous on the UI thread, so the
                // user sees the spinner + label flip within one frame of
                // the tap regardless of how slow the rest of the chain
                // (permission dialogs, gRPC round-trips) turns out to be.
                // The verb is the present-continuous form of the button
                // label: "Activate" / "Re-Activate" both map to
                // "Activating".
                // Capture the chain epoch immediately after _beginActivation
                // so every async pre-_doActivate callback (CAMERA permission,
                // RECORD_AUDIO permission, purge-done) is gated by _withEpoch.
                // Without this, a late permission-denied callback from a chain
                // the user already superseded by Deactivating would clear the
                // live Deactivate cue.
                var epoch = builtin._beginActivation("Activating")
                androidPermissions.requestCameraPermission(builtin._withEpoch(epoch, function(camGranted) {
                    if (!camGranted) {
                        permDeniedDialog.missing = "CAMERA"
                        permDeniedDialog.open()
                        builtin._endActivation()
                        return
                    }
                    androidPermissions.requestRecordAudioPermission(builtin._withEpoch(epoch, function(micGranted) {
                        if (!micGranted) {
                            permDeniedDialog.missing = "RECORD_AUDIO"
                            permDeniedDialog.open()
                            builtin._endActivation()
                            return
                        }
                        // Re-Activate flicker race: settingsController.activate()
                        // is deferred until BOTH AddInput RPCs succeed (see
                        // _doActivate). Between this tap and that deferred call
                        // the m_userIntentEpoch is unchanged, so any
                        // getInputsInfo reconcile reply that landed BEFORE the
                        // AddInputs complete (for example the purge step has
                        // removed the priority-0 inputs but not re-added them
                        // yet) would observe "no inputs" and call
                        // setActiveFromReconciliation(false) using the still-
                        // valid pre-tap epoch — clobbering m_active=true and
                        // briefly flipping the Active button to Activate.
                        //
                        // Bump the epoch NOW so any in-flight reconcile reply
                        // is dropped on arrival, well before the activate()
                        // commit at the end of _doActivate. (A second bump
                        // happens inside activate() itself; the QML reconciler
                        // is idempotent under repeated bumps.)
                        if (settingsController) {
                            settingsController.bumpUserIntentEpoch()
                        }
                        builtin._ensureFFStreamCameraDaemonReady(epoch, function() {
                            // Purge any prior priority-0 builtin inputs first,
                            // so Re-Activate doesn't duplicate them. The purge
                            // targets the camera daemon (port 3594) — the same
                            // client _doActivate will issue AddInput against.
                            // Purge-done routes through _withEpoch too (L1):
                            // a stale purge completion from a superseded chain
                            // must NOT call _doActivate, which would dispatch
                            // a fresh 4-leg chain against a chain the user has
                            // already moved on from.
                            if (builtin.root && builtin.root.ffstreamCameraClient) {
                                builtin._purgeBuiltinInputs(builtin.root.ffstreamCameraClient,
                                    builtin._withEpoch(epoch, function() {
                                        builtin._doActivate(true)
                                    }))
                            } else {
                                builtin._doActivate(true)
                            }
                        })
                    }))
                }))
            }
        }

        Button {
            Layout.fillWidth: true
            font.pointSize: 20
            text: "Deactivate"
            // Disable while ANY chain (Activate or Deactivate) is in
            // flight, in addition to the existing "must currently be
            // active" gate. The watchdog re-enables this on timeout.
            enabled: settingsController.active && !builtin._activationInFlight

            onClicked: {
                builtin._doDeactivate()
            }
        }
    }
}
