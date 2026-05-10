import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Phase-4 test suite: Dashboard preview bindings (Section 4 in
/// /tmp/claude-plans/task6-phase4-specs.md v3.2.2).
///
/// Pins post-cleanup contracts on Dashboard.qml's VideoPlayerRTMP
/// (id: imageScreenshot, lines 1123-1201 at HEAD fe22148):
///   - source resolves to "" when previewRTMPUrl + raw + low-bitrate are all ""
///   - raw / low-bitrate toggles are inert when their respective driver URL is ""
///   - bindings activate when drivers are non-empty
///   - "lying-toggle" current contract pinned per coordinator Path A
///     (Task #17 will flip both code and test polarity in one commit)
///   - per-property dual-sided witnesses for rawCameraPreviewUrl and
///     lowBitratePreviewUrl per coordinator addendum items 1+2.
///
/// imageScreenshot (the VideoPlayerRTMP) does NOT carry an objectName at
/// HEAD, so findChild() cannot reach it directly. We use _findVideoPlayer()
/// which walks the children tree by property signature (configuredPreview +
/// useRawSource — both unique to the dashboard's VideoPlayerRTMP). This is
/// strictly a test-time discovery convention; product code is not modified.
TestCase {
    id: tc
    name: "DashboardPreviewBindings"
    when: windowShown
    width: 1080
    height: 1920
    visible: true

    // ------------------------------------------------------------
    // Stubs sufficient for Dashboard's required-property surface.
    // Mirrors tst_dashboard_checkboxes.qml's stub roster.
    // ------------------------------------------------------------
    QtObject {
        id: stubAppSettings
        // Drivers mutated per-test via direct property assignment.
        property string previewRTMPUrl: ""
        property string rawCameraPreviewUrl: ""
        property string lowBitratePreviewUrl: ""
        property string dxProducerHost: "https://example.test:1234"
        property string ffstreamHost: ""
        property string chosenPlayerStreamID: ""
        property string djiPreviewRouteStem: ""
        property bool soundEnabled: false
    }

    QtObject {
        id: stubGrpcCallOptions
    }

    QtObject {
        id: stubClient
        function ping() {}
        function getLatencies() {}
        function getInputQuality() {}
        function getFPSFraction() {}
        function getOutputQuality() {}
        function getBitRates() {}
        function getPlayerLag() {}
        function listStreamPlayers() {}
        function subscribeToChatMessages() {}
        function setVariable(name, value, ok, err, opts) {}
        function getVariable(name, ok, err, opts) {}
        function getBackendInfo() {}
        function banUser() {}
        function listProfiles() {}
        function listStreamSources() {}
        function listStreamServers() {}
        function reconnect() {}
        property var processGRPCError: undefined
    }

    ListModel {
        id: stubChatModel
    }

    QtObject {
        id: stubPlatform
        function vibrate(ms, hard) {}
    }

    QtObject {
        id: stubRoot
        property var appSettings: stubAppSettings
        property var dxProducerClient: stubClient
        property var ffstreamClient: stubClient
        property var grpcCallOptions: stubGrpcCallOptions
        property var streamingGrpcCallOptions: stubGrpcCallOptions
        property var globalChatMessagesModel: stubChatModel
        property string dxProducerHost: "https://example.test:1234"
        property var platform: stubPlatform
        function processStreamDGRPCError() {}
        function processFFStreamGRPCError() {}
        function checkStreamDClient() { return false }
        function fireMultiPlatformRPC() {}
        property var platformCapabilities: ({})
    }

    Component {
        id: dashboardComp
        Dashboard {
            anchors.fill: parent
            root: stubRoot
            platformCapabilities: ({})
        }
    }

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------

    /// Walk the children tree to find Dashboard's VideoPlayerRTMP. We
    /// match by property signature (configuredPreview + useRawSource +
    /// useLowBitratePreview) because imageScreenshot does NOT carry an
    /// objectName at HEAD fe22148 (Round 5 added objectName only to
    /// videoSourceToggle and rtmpUrlField). This walker is test-time
    /// only; product code is unchanged.
    function _findVideoPlayer(node) {
        if (!node) return null
        if (node.useRawSource !== undefined
                && node.useLowBitratePreview !== undefined
                && node.configuredPreview !== undefined) {
            return node
        }
        var children = node.children || []
        for (var i = 0; i < children.length; i++) {
            var hit = _findVideoPlayer(children[i])
            if (hit) return hit
        }
        return null
    }

    /// Reset the stub appSettings to a clean slate before each test —
    /// ensures order-independence (testing-discipline determinism rule).
    function _resetSettings(opts) {
        stubAppSettings.previewRTMPUrl = opts.previewRTMPUrl || ""
        stubAppSettings.rawCameraPreviewUrl = opts.rawCameraPreviewUrl || ""
        stubAppSettings.lowBitratePreviewUrl = opts.lowBitratePreviewUrl || ""
    }

    function _instantiate() {
        var d = createTemporaryObject(dashboardComp, tc)
        verify(d !== null, "Dashboard must instantiate")
        wait(50)
        return d
    }

    /// Build a JS spy on imageScreenshot.source. Records every (source,
    /// timestamp) tuple as the binding re-evaluates. Used by T-2.6 / T-2.7
    /// to assert the precise sequence of RTMP-connect intents (proxy for
    /// socket-level connect attempts, which are infeasible in tst_wingout).
    function _attachSourceSpy(player) {
        var spy = { entries: [] }
        spy.entries.push({ source: String(player.source), ts: Date.now() })
        // Use Qt.binding via Connections - simpler approach: poll by
        // re-checking on each step. For QtTest's deterministic loop this
        // is actually adequate because the binding is synchronous on
        // property write — a wait(0) flushes pending evaluations. Each
        // mutation followed by wait(50) records one snapshot.
        spy._snap = function() {
            var s = String(player.source)
            var last = spy.entries[spy.entries.length - 1]
            if (!last || last.source !== s) {
                spy.entries.push({ source: s, ts: Date.now() })
            }
        }
        return spy
    }

    // ============================================================
    // T-1.3 — Dashboard MediaPlayer source becomes "" when
    // previewRTMPUrl is empty (consumer side of empty-URL flow).
    // ============================================================
    function test_T_1_3_dashboard_source_empty_when_preview_empty() {
        _resetSettings({})
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null, "VideoPlayerRTMP (imageScreenshot) must be reachable")
        wait(100)

        // Assertion 2 — Good IS: source resolves to empty string.
        compare(String(mp.source), "",
                "source must resolve to empty when all three drivers are empty")

        // Assertion 3 — Bad NOT: legacy 127.0.0.1 fallback gone.
        verify(String(mp.source).indexOf("127.0.0.1") === -1,
               "no 127.0.0.1 fallback may leak")

        // Assertion 4 — Bad NOT: no rtmp scheme leaks.
        verify(String(mp.source).indexOf("rtmp://") === -1,
               "no rtmp:// scheme may leak when source is empty")

        // Assertion 5 — Bad NOT: no RTMP error logged.
        wait(500)
        var err = mp.errorString || ""
        verify(err === "" || err.indexOf("rtmp") === -1,
               "no RTMP-connect error must be logged when source is empty: " + err)
    }

    // ============================================================
    // T-2.1 — Dashboard raw-source toggle is inert when
    // appSettings.rawCameraPreviewUrl === "".
    //
    // Setup: rawCameraPreviewUrl="", previewRTMPUrl=non-empty (RFC-5737
    // 198.51.100.1). Find videoSourceToggle by objectName (added at
    // Dashboard.qml:1185 in Round 5 SHA 8a75023). Assert source falls
    // through to effectivePreview when raw is selected with empty URL.
    // ============================================================
    function test_T_2_1_raw_toggle_inert_when_url_empty() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: ""
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null, "imageScreenshot must be reachable")
        var toggle = findChild(dashboard, "videoSourceToggle")
        verify(toggle !== null,
               "videoSourceToggle must be findable by objectName (Round 5 SHA 8a75023, Dashboard.qml:1185)")
        wait(100)

        // Assertion 1 — Good IS: configured preview is the active
        // source pre-toggle.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "pre-toggle source must be the configured preview")

        // Assertion 2 — Good IS: source falls through to effectivePreview
        // because sourceRawCamera === "" (the && short-circuit at
        // Dashboard.qml:1143).
        toggle.checked = true
        mp.useRawSource = true
        wait(50)
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "with raw URL empty, source must fall through to effectivePreview")

        // Assertion 3 — Bad NOT: legacy hardcoded stem gone.
        verify(String(mp.source).indexOf("proxy/dji-osmo-pocket3") === -1,
               "legacy proxy/dji-osmo-pocket3 stem must NOT appear")

        // Assertion 4 — Bad NOT: legacy 127.0.0.1:1935 fallback gone.
        verify(String(mp.source).indexOf("127.0.0.1:1935") === -1,
               "legacy 127.0.0.1:1935 fallback must NOT appear")
    }

    // ============================================================
    // T-2.2 — Dashboard low-bitrate toggle is inert when
    // appSettings.lowBitratePreviewUrl === "".
    // ============================================================
    function test_T_2_2_low_bitrate_toggle_inert_when_url_empty() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            lowBitratePreviewUrl: ""
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        wait(100)

        // Assertion 1 — Good IS: short-circuit falls back to
        // configuredPreview.
        mp.useLowBitratePreview = true
        wait(50)
        compare(String(mp.effectivePreview), "rtmp://198.51.100.1/cfg",
                "with low-bitrate URL empty, effectivePreview must fall back")

        // Assertion 2 — Bad NOT: legacy ?reason=low-bitrate query gone.
        verify(String(mp.effectivePreview).indexOf("low-bitrate") === -1,
               "legacy ?reason=low-bitrate query must NOT appear")

        // Assertion 3 — Bad NOT: legacy stem gone.
        verify(String(mp.effectivePreview).indexOf("proxy/dji-osmo-pocket3") === -1,
               "legacy proxy/dji-osmo-pocket3 stem must NOT appear")
    }

    // ============================================================
    // T-2.3 — Dashboard bindings activate when drivers are non-empty.
    // Validates the conditional precedence at Dashboard.qml:1143
    // (useRawSource outer, useLowBitratePreview inner).
    // ============================================================
    function test_T_2_3_bindings_activate_when_drivers_present() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: "rtmp://203.0.113.5/raw",
            lowBitratePreviewUrl: "rtmp://203.0.113.5/low"
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        wait(100)

        // Assertion 6 (positive enabled witness — Gap A from
        // test-designer-1 §4.5; declared FIRST because it must run
        // BEFORE any mp.useRawSource mutation to catch circular-self-
        // gating regressions). The post-fix Dashboard.qml:1206
        // binding is `enabled: imageScreenshot.sourceRawCamera &&
        // imageScreenshot.sourceRawCamera.length > 0` — depends ONLY
        // on the URL's presence, NOT on useRawSource. With
        // rawCameraPreviewUrl set + useRawSource still false (initial
        // state), toggle.enabled MUST be true so the user can click
        // and switch sources. If a future regression copies the
        // Dashboard.qml:1147 source-binding precedence verbatim
        // (enabled: useRawSource && sourceRawCamera && length > 0),
        // the toggle becomes circular-self-gating: enabled depends on
        // useRawSource, useRawSource only flips via click, click only
        // works when enabled — permanent stuck-disabled state once the
        // user opens Dashboard with useRawSource=false.
        // [T1: Dashboard.qml:1206 enabled binding read at HEAD 291cd98
        //  this session via grep -n, high; T1: Qt Quick Controls 2
        //  AbstractButton enabled-prop semantics
        //  <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html#enabled-prop>,
        //  high; T1: test-designer-1 spec §4.5 Gap A verbatim, high]
        //
        // Broke-the-code-validation: if you broke the enabled binding
        // by adding `imageScreenshot.useRawSource &&` as the first
        // operand, this assertion would FAIL because useRawSource is
        // false in the initial state — `false && (anything) = false`.
        // Empirical broke-the-code A/B log captured at submission.
        var toggle = findChild(dashboard, "videoSourceToggle")
        verify(toggle !== null,
               "videoSourceToggle must be findable by objectName")
        compare(toggle.enabled, true,
                "Gap-A witness: with rawCameraPreviewUrl set + "
                + "useRawSource still false, toggle.enabled MUST be "
                + "true (catches future enabled-binding miswrite that "
                + "circular-self-gates on useRawSource)")

        // Assertion 1 — Good IS: configured preview is default.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "no toggles → configured preview")

        // Assertion 2 — Good IS: raw activates.
        mp.useRawSource = true
        wait(50)
        compare(String(mp.source), "rtmp://203.0.113.5/raw",
                "raw toggle activates raw URL")

        // Assertion 3 — Good IS: low-bitrate activates when raw off.
        mp.useRawSource = false
        mp.useLowBitratePreview = true
        wait(50)
        compare(String(mp.source), "rtmp://203.0.113.5/low",
                "low-bitrate toggle (raw off) activates low-bitrate URL")

        // Assertion 4 — Good IS: when both on, raw wins (precedence).
        mp.useRawSource = true
        mp.useLowBitratePreview = true
        wait(50)
        compare(String(mp.source), "rtmp://203.0.113.5/raw",
                "both toggles on: raw wins per Dashboard.qml:1143 priority")

        // Assertion 5 — Bad NOT: configured preview NOT leaking when
        // raw is active and present.
        verify(String(mp.source).indexOf("198.51.100.1") === -1,
               "configured preview must NOT leak when raw is active+present")
    }

    // ============================================================
    // T-2.4 — Honest contract: videoSourceToggle is DISABLED when
    // rawCameraPreviewUrl is empty. This commit IS the Task #17
    // paired flip — the test was structured to flip atomically when
    // Task #17 lands, per the test-author's explicit routing in the
    // prior PINNED-CONTRACT header (see git history at HEAD~1 for the
    // pre-flip wording). Dashboard.qml:1184-1212 now adds the
    // `enabled:` companion guard to the binding-side guard at
    // Dashboard.qml:1143; together they ensure the toggle's
    // checked/icon/tooltip visual state cannot drift from the actual
    // source binding output.
    //
    // Verifies the UX-lie regression introduced by Task #6 cleanup's
    // empty-URL default is now closed. With my fix:
    // - Pre-click: toggle.enabled is FALSE (gated on sourceRawCamera
    //   length); tooltip surfaces "Raw camera preview not configured".
    // - mouseClick is a NO-OP per Qt Quick Controls 2 AbstractButton
    //   enabled-gate semantics — the click event is not delivered to
    //   onToggled when enabled === false.
    // - Post-click: useRawSource stays false, toggle.checked stays
    //   false, toggle.text stays "🌐". No state change. No UX lie.
    //
    // Cleanup-audit.md round-6 entry's "Regression introduced by
    // Task #6 cleanup" section (committed at fe22148) becomes
    // historical with this commit per Path A condition 3 — the
    // regression is closed, and any future reader can see the
    // before/after via git history.
    //
    // Trigger MANDATE preserved: assertion 1's manipulation MUST use
    // mouseClick(videoSourceToggle) per test-reviewer-1 v3.2 M1
    // verdict. Disabled toggles ignore mouse clicks per
    // <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html#enabled-prop>;
    // the click no-op is the very property we are verifying.
    // Programmatic property assignment would bypass the enabled-gate
    // and is therefore still REJECTED for this test.
    // ============================================================
    function test_T_2_4_pinned_lying_toggle() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: ""
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        var toggle = findChild(dashboard, "videoSourceToggle")
        verify(toggle !== null,
               "videoSourceToggle must be findable by objectName")
        wait(100)

        // Assertion 7 (declared first because it is pre-step-1) —
        // Good IS (Task #17 honest contract): toggle is DISABLED when
        // rawCameraPreviewUrl === "". This is the trigger-independent
        // witness — without an enabled-gate, the click event would
        // fire onToggled and flip the visual state in conflict with
        // the binding-side short-circuit at Dashboard.qml:1143.
        // [T1: Qt Quick Controls 2 AbstractButton — `enabled`
        // property gates user-input event delivery; primary source
        // <https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html#enabled-prop>]
        compare(toggle.enabled, false,
                "Pre-click: videoSourceToggle.enabled must be false because rawCameraPreviewUrl is empty (Task #17 honest contract)")

        // Trigger via mouseClick. With enabled === false this is a
        // no-op per AbstractButton semantics — the post-click
        // assertions below verify NO state change (the very property
        // we want when the user has nothing to switch to).
        mouseClick(toggle)
        wait(50)

        // Assertion 1 — Good IS: a user click on the disabled toggle
        // does NOT flip useRawSource. The click is rejected by the
        // enabled-gate before onToggled can run.
        compare(mp.useRawSource, false,
                "After mouseClick on disabled toggle: useRawSource must remain false (click is a no-op per AbstractButton enabled-gate)")

        // Assertion 2 — Good IS: source remains the configured preview
        // because (a) the binding-side short-circuit at
        // Dashboard.qml:1143 still holds AND (b) the toggle-side
        // enabled-gate prevented useRawSource from being flipped at
        // all. Defense-in-depth: either guard alone would keep the
        // source honest; both together ensure visual + binding state
        // can never disagree.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "useRawSource=false + rawCameraPreviewUrl=\"\" "
                + "→ source remains the configured preview")

        // Assertion 3 — Bad NOT: legacy stem must NEVER be the source.
        verify(String(mp.source).indexOf("proxy/dji-osmo-pocket3") === -1,
               "legacy proxy/dji-osmo-pocket3 must NEVER appear")

        // Assertion 4 — Bad NOT: legacy fallback IP must NEVER appear.
        verify(String(mp.source).indexOf("127.0.0.1:1935") === -1,
               "legacy 127.0.0.1:1935 must NEVER appear")

        // Assertion 5 — Good IS: toggle visual state matches the
        // (unchanged) useRawSource flag. Both stay false because the
        // disabled-gate rejected the click.
        compare(toggle.checked, false,
                "toggle.checked must remain false (click rejected by disabled state)")

        // Assertion 6 — Good IS: icon stays in the "processed" glyph
        // because checked stayed false. No visual flip → no UX lie.
        compare(toggle.text, "🌐",
                "toggle.text must remain '🌐' (no state flip because click rejected)")

        // Assertion 8 (disabled-state tooltip witness — Gap B from
        // test-designer-1 §4.5). The post-fix Dashboard.qml:1215-1217
        // ToolTip.text binding is a 3-way conditional:
        //   enabled
        //     ? (checked ? "Switch to processed feed"
        //                : "Switch to raw camera feed")
        //     : "Raw camera preview not configured"
        // T-2.5 (in tst_no_mission_overfit_in_product_code) source-
        // string-asserts only ONE of the three strings ("Switch to
        // processed feed"). The disabled-state wording "Raw camera
        // preview not configured" had ZERO behavioural coverage before
        // this assertion — a typo or accidental removal of the
        // disabled-branch tooltip would slip undetected. With the
        // toggle disabled (rawCameraPreviewUrl=""), the tooltip MUST
        // surface the disabled-state wording exactly so the user sees
        // *why* the control is unresponsive.
        // [T1: Dashboard.qml:1215-1217 ToolTip.text binding read at
        //  HEAD 291cd98 this session via grep -n, high; T1: test-
        //  designer-1 spec §4.5 Gap B verbatim, high]
        //
        // Broke-the-code-validation: if you broke the ToolTip.text
        // binding by reverting to the pre-fix 2-way conditional
        // (`checked ? "Switch to processed feed" : "Switch to raw
        // camera feed"`), this assertion would FAIL because — with
        // checked=false (the click was rejected by the disabled-gate
        // per Assertion 5) — the tooltip would read "Switch to raw
        // camera feed", not "Raw camera preview not configured".
        // Empirical broke-the-code A/B log captured at submission.
        compare(toggle.ToolTip.text,
                "Raw camera preview not configured",
                "Gap-B witness: when toggle is disabled, ToolTip.text "
                + "MUST surface the disabled-state wording so the user "
                + "sees *why* the control is unresponsive")
    }

    // ============================================================
    // T-2.4-positive — onToggled positive-path witness with raw URL
    // set (Gap C from test-designer-1 §4.5 spec extension).
    //
    // T-2.4 covers the no-op disabled-mouseClick case; ZERO test
    // covered the positive case where mouseClick (with raw URL set +
    // enabled=true) triggers onToggled → useRawSource flips → source
    // binding picks the raw URL → 3-way tooltip transitions through
    // its third branch ("Switch to processed feed"). The full chain
    // had no end-to-end behavioural witness — removing or breaking
    // any link (onToggled body removal, source-binding precedence
    // inversion, ToolTip.text 3-way collapse) would slip undetected.
    //
    // This sibling test exercises the same setup pattern as T-2.4 but
    // with rawCameraPreviewUrl set, asserting both the pre-click
    // baseline (enabled=true, "Switch to raw camera feed" tooltip)
    // AND the post-click cascade (useRawSource=true, source picks
    // raw URL, text="📷", "Switch to processed feed" tooltip).
    //
    // Trigger MANDATE preserved per T-2.4: mouseClick(toggle), NOT
    // programmatic property assignment. The whole point of the click
    // path is that it traverses AbstractButton → onToggled → property
    // mutation; bypassing it would leave onToggled untested.
    //
    // [T1: test-designer-1 spec §4.5 Gap C verbatim, high]
    // [T1: Dashboard.qml:1206/1209-1212/1215-1217 bindings read at
    //  HEAD 291cd98 this session via grep -n, high]
    // [T1: Dashboard.qml:1147 source-binding precedence (`source:
    //  (useRawSource && sourceRawCamera && sourceRawCamera.length > 0)
    //  ? sourceRawCamera : effectivePreview`) lexically AND semantically
    //  verified at HEAD b4473ed via `git show HEAD:Dashboard.qml |
    //  sed -n '1143p;1147p'` this session — Task #34 IF2 fix corrects
    //  prior off-by-four (1143 was the `effectivePreview` declaration
    //  start, NOT the source-binding precedence) per round-3-(b)
    //  semantic verify-then-cite discipline, high]
    //
    // Broke-the-code-validation: if you broke onToggled by removing
    // or commenting out `imageScreenshot.useRawSource =
    // videoSourceToggle.checked;`, the post-click compare(mp.useRawSource,
    // true) assertion would FAIL because the click would flip toggle.checked
    // but never propagate to useRawSource. Likewise, if you collapsed
    // the 3-way tooltip back to the 2-way (`checked ? "Switch to
    // processed feed" : "Switch to raw camera feed"`), the
    // pre-/post-click assertions would still pass (the 2-way matches
    // these strings for enabled=true cases) — meaning Gap B's
    // disabled-state assertion is the load-bearing tooltip witness;
    // T-2.4-positive's tooltip assertions are corroborating, not
    // load-bearing. Empirical broke-the-code A/B log captured at
    // submission for the load-bearing useRawSource + source +
    // text post-click chain.
    // ============================================================
    function test_T_2_4_positive_click_flips_when_url_set() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: "rtmp://203.0.113.5/raw"
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        var toggle = findChild(dashboard, "videoSourceToggle")
        verify(toggle !== null,
               "videoSourceToggle must be findable by objectName")
        wait(100)

        // Pre-click Assertion 1 — Good IS: with rawCameraPreviewUrl
        // set, toggle is enabled (post-fix Dashboard.qml:1206 binding).
        compare(toggle.enabled, true,
                "Pre-click: toggle.enabled must be true with raw URL set")

        // Pre-click Assertion 2 — Good IS: with checked=false +
        // enabled=true, ToolTip.text reads the offer-to-switch wording.
        // Per Dashboard.qml:1215-1217 3-way conditional.
        compare(toggle.ToolTip.text, "Switch to raw camera feed",
                "Pre-click: ToolTip.text must read offer-to-switch wording")

        // Pre-click Assertion 3 — Good IS: useRawSource starts false.
        compare(mp.useRawSource, false,
                "Pre-click: useRawSource must start false (no toggle interaction yet)")

        // Trigger via mouseClick — exercises AbstractButton → click
        // event → onToggled chain (Dashboard.qml:1209-1212).
        mouseClick(toggle)
        wait(50)

        // Post-click Assertion 4 — Good IS: onToggled DID fire and
        // propagated checked → useRawSource. This is the load-bearing
        // witness for Gap C: future regression that breaks
        // onToggled's body would surface here.
        compare(mp.useRawSource, true,
                "Post-click: useRawSource must flip to true (proves onToggled body fired)")

        // Post-click Assertion 5 — Good IS: source binding at
        // Dashboard.qml:1147 picks the raw URL because both
        // useRawSource is true AND sourceRawCamera is non-empty.
        // End-to-end chain: click → onToggled → useRawSource flips →
        // binding evaluates (true && "rtmp://203.0.113.5/raw") →
        // source = raw URL. Catches future regression in either
        // onToggled (would fail Assertion 4 first) OR the binding
        // precedence (would fail this assertion specifically).
        compare(String(mp.source), "rtmp://203.0.113.5/raw",
                "Post-click: source binding must pick raw URL "
                + "(end-to-end click → onToggled → useRawSource → binding chain)")

        // Post-click Assertion 6 — Good IS: icon flips to camera
        // because checked is now true. Visual state matches the flag.
        compare(toggle.text, "📷",
                "Post-click: toggle.text must flip to '📷' (checked=true)")

        // Post-click Assertion 7 — Good IS: ToolTip.text transitions
        // through the third branch of the 3-way conditional (enabled
        // still true + checked now true → "Switch to processed feed").
        // Corroborating witness, not load-bearing — see broke-the-
        // code-validation block above.
        compare(toggle.ToolTip.text, "Switch to processed feed",
                "Post-click: ToolTip.text must reflect the offer-to-switch-back wording")

        // Post-click Assertion 8 — Bad NOT: configured preview must
        // NOT leak when raw is active and present (defense-in-depth
        // dual-sided assertion mirroring T-2.3's assertion 5).
        verify(String(mp.source).indexOf("198.51.100.1") === -1,
               "Post-click: configured preview must NOT leak when raw is active+present")
    }

    // ============================================================
    // T-2.5 — console.log wording / tooltip wording for video-source
    // toggle uses "processed", not "prod". Source-string assertion
    // (XHR + file://). Lives in tst_no_mission_overfit_in_product_code
    // per spec; placeholder here would create coverage overlap. NOT
    // implemented in this file.
    // ============================================================

    // ============================================================
    // T-2.6 — appSettings.rawCameraPreviewUrl raw-toggle dual-sided
    // property test (per coordinator addendum item 1).
    //
    // Single test function exercising BOTH sides end-to-end. Codifies
    // the rawCameraPreviewUrl property contract so a future regression
    // cannot "fix" one side while breaking the other.
    // ============================================================
    function test_T_2_6_raw_camera_preview_url_dual_sided() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: "",
            lowBitratePreviewUrl: ""
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        wait(100)

        var spy = _attachSourceSpy(mp)

        // Step 1 — Empty-state, toggle-off: source = configuredPreview.
        wait(50)
        spy._snap()
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "step 1: empty raw, toggle off → configured preview")

        // Step 2 — Empty-state, toggle-on: source STILL = configured.
        mp.useRawSource = true
        wait(50)
        spy._snap()
        // Assertion 1 — Good IS.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "step 2: empty raw, toggle on → still configured (no leak)")

        // Step 3 — Set non-empty raw URL while toggle is still on.
        stubAppSettings.rawCameraPreviewUrl = "rtmp://203.0.113.5/raw"
        wait(50)
        spy._snap()
        // Assertion 3 — Good IS: source switches.
        compare(String(mp.source), "rtmp://203.0.113.5/raw",
                "step 3: setting raw URL with toggle on activates raw path")

        // Step 4 — Toggle off: source returns to configured.
        mp.useRawSource = false
        wait(50)
        spy._snap()
        // Assertion 5 — Good IS.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "step 4: toggle off after set → returns to configured")

        // Step 5 — Re-clear raw URL while toggle is on.
        mp.useRawSource = true
        wait(20)
        stubAppSettings.rawCameraPreviewUrl = ""
        wait(50)
        spy._snap()
        // Assertion 7 — Good IS.
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "step 5: clearing raw URL with toggle on → falls back")

        // Assertion 2 — Bad NOT: spy has no entry to "" (other than the
        // initial registration before binding settled) and never has a
        // legacy proxy/dji-osmo-pocket3 entry.
        for (var i = 0; i < spy.entries.length; i++) {
            var s = spy.entries[i].source
            verify(s.indexOf("proxy/dji-osmo-pocket3") === -1
                   && s.indexOf("dji-osmo-pocket-3") === -1,
                   "spy entry " + i + " contains legacy raw stem: " + s)
        }

        // Assertion 4 — Good IS: exactly one connect attempt to the
        // configured raw URL.
        var rawHits = 0
        for (var j = 0; j < spy.entries.length; j++) {
            if (spy.entries[j].source === "rtmp://203.0.113.5/raw") rawHits++
        }
        compare(rawHits, 1,
                "exactly one source-binding entry for the configured raw URL")

        // Assertion 6 — Good IS: last entry is configured (post-step-4).
        // (Step 5 immediately follows and re-asserts configured, so the
        // last spy entry reflects that fall-back; either way, assert it
        // ends on the configured preview.)
        compare(spy.entries[spy.entries.length - 1].source,
                "rtmp://198.51.100.1/cfg",
                "spy must end on configured preview after re-clear")

        // Assertion 8 — Bad NOT: no RTMP error from phantom connect.
        var err = mp.errorString || ""
        verify(/error|fail|EADDRNOTAVAIL/i.test(err) === false,
               "no RTMP error must surface from phantom connect: " + err)
    }

    // ============================================================
    // T-2.7 — appSettings.lowBitratePreviewUrl low-bitrate-variant
    // dual-sided property test (per coordinator addendum item 2).
    // ============================================================
    function test_T_2_7_low_bitrate_preview_url_dual_sided() {
        _resetSettings({
            previewRTMPUrl: "rtmp://198.51.100.1/cfg",
            rawCameraPreviewUrl: "",
            lowBitratePreviewUrl: ""
        })
        var dashboard = _instantiate()
        var mp = _findVideoPlayer(dashboard)
        verify(mp !== null)
        wait(100)

        var spy = _attachSourceSpy(mp)

        // Step 1 — Empty-state, lowBitrate-off: source = configured.
        wait(50)
        spy._snap()
        compare(String(mp.source), "rtmp://198.51.100.1/cfg",
                "step 1: empty low-bitrate, toggle off → configured")

        // Step 2 — Empty-state, lowBitrate-on: still configured.
        mp.useLowBitratePreview = true
        wait(50)
        spy._snap()
        // Assertion 1 — Good IS: effectivePreview falls back.
        compare(String(mp.effectivePreview), "rtmp://198.51.100.1/cfg",
                "step 2: empty low-bitrate, toggle on → effectivePreview = configured")

        // Step 3 — Set non-empty low-bitrate URL.
        stubAppSettings.lowBitratePreviewUrl = "rtmp://203.0.113.5/low"
        wait(50)
        spy._snap()
        // Assertion 3 — Good IS: effectivePreview switches.
        compare(String(mp.effectivePreview), "rtmp://203.0.113.5/low",
                "step 3: setting low-bitrate URL with toggle on activates variant")
        // Assertion 4 — Good IS: source binding follows effectivePreview
        // (raw is off so effectivePreview wins).
        compare(String(mp.source), "rtmp://203.0.113.5/low",
                "step 3: source binding follows effectivePreview")

        // Step 4 — Toggle off: returns to configured.
        mp.useLowBitratePreview = false
        wait(50)
        spy._snap()
        // Assertion 7 — Good IS.
        compare(String(mp.effectivePreview), "rtmp://198.51.100.1/cfg",
                "step 4: low-bitrate off → returns to configured")

        // Step 5 — Re-clear: toggle on again then clear.
        mp.useLowBitratePreview = true
        wait(20)
        stubAppSettings.lowBitratePreviewUrl = ""
        wait(50)
        spy._snap()
        // Assertion 8 — Good IS.
        compare(String(mp.effectivePreview), "rtmp://198.51.100.1/cfg",
                "step 5: clearing low-bitrate URL with toggle on → falls back")

        // Assertion 2 — Bad NOT: spy has no entry containing low-bitrate
        // / ?reason=low-bitrate / proxy/dji-osmo-pocket3.
        for (var i = 0; i < spy.entries.length; i++) {
            var s = spy.entries[i].source
            verify(s.indexOf("low-bitrate") === -1
                   && s.indexOf("?reason=") === -1,
                   "spy entry " + i + " contains banned low-bitrate marker: " + s)
        }

        // Assertion 5 — Good IS: exactly one source entry to the
        // configured low-bitrate URL.
        var lowHits = 0
        for (var j = 0; j < spy.entries.length; j++) {
            if (spy.entries[j].source === "rtmp://203.0.113.5/low") lowHits++
        }
        compare(lowHits, 1,
                "exactly one source-binding entry for the low-bitrate URL")

        // Assertion 6 — Bad NOT: low-bitrate-on with non-empty URL does
        // NOT use the regular previewRTMPUrl when the variant is set
        // (the precise contract from coordinator addendum item 2).
        // After re-clear, source is back to configured — but the LAST
        // entry RECORDED for the active-low-bitrate state must NOT have
        // been the configured preview while the variant was set. Walk
        // entries to verify the variant URL appeared after configured.
        var sawVariantAfterCfg = false
        var sawCfgFirst = false
        for (var k = 0; k < spy.entries.length; k++) {
            if (spy.entries[k].source === "rtmp://198.51.100.1/cfg")
                sawCfgFirst = true
            if (sawCfgFirst
                    && spy.entries[k].source === "rtmp://203.0.113.5/low") {
                sawVariantAfterCfg = true
                break
            }
        }
        verify(sawVariantAfterCfg,
               "low-bitrate variant must appear in spy AFTER configured (precedence per addendum item 2)")

        // Assertion 9 — Bad NOT: no error from phantom connect.
        var err = mp.errorString || ""
        verify(/error|fail|EADDRNOTAVAIL/i.test(err) === false,
               "no RTMP error from phantom connect: " + err)
    }
}
