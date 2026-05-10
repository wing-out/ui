import QtQuick
import QtQuick.Controls
import QtTest
import WingOut
import RemoteCameraController

/// Phase-4 test suite: DJIControl rtmpUrlField text-binding derivation
/// (Section 7 in /tmp/claude-plans/task6-phase4-specs.md v3.2.2).
///
/// Pins post-cleanup contracts on DJIControl.qml's rtmpUrlField text
/// binding (lines 262-282 at HEAD fe22148; objectName at L264 added by
/// Round 5 SHA 8a75023):
///
///   text: {
///       var ip = djiControlPage.root.platform.hotspotIPAddress
///       if (!ip) ip = DJIController.localWlan1Ip
///       var stem = djiControlPage.root.appSettings
///               ? djiControlPage.root.appSettings.djiPreviewRouteStem
///               : ""
///       return (ip && stem && stem.length > 0)
///           ? "rtmp://" + ip + ":1935/" + stem
///           : ""
///   }
///
/// All 7 tests target this binding via findChild(djiControl, "rtmpUrlField")
/// (objectName-anchored). Walking TextField siblings is REJECTED.
///
/// DJIController is a QML_SINGLETON with localWlan1Ip as a READ-only
/// Q_PROPERTY (see dji_controller.h:25). Tests set platform.hotspotIPAddress
/// non-empty so the localWlan1Ip fallback is unreachable; T-5.6 relies on
/// the singleton's freshly-instantiated default ("" — no Wi-Fi adapter in
/// the headless environment, asserted in-test).
TestCase {
    id: tc
    name: "DJIControlRtmpUrlField"
    when: windowShown
    width: 1080
    height: 1920
    visible: true

    // ---- Stubs ----
    QtObject {
        id: stubAppSettings
        property string djiPreviewRouteStem: ""
        property string dxProducerHost: "https://example.test:1234"
    }

    QtObject {
        id: stubPlatform
        property string hotspotIPAddress: ""
        property bool isLocalHotspotEnabled: false
        property bool isHotspotEnabled: false
        function refreshWiFiState() {}
        function getLocalOnlyHotspotInfo() { return null }
        function getHotspotConfiguration() { return null }
    }

    QtObject {
        id: stubRoot
        property var appSettings: stubAppSettings
        property var platform: stubPlatform
    }

    // QtObject root used for the appSettings === null variant (T-5.7).
    QtObject {
        id: stubRootNullAppSettings
        property var appSettings: null
        property var platform: stubPlatform
    }

    Component {
        id: djiControlComp
        DJIControl {
            anchors.fill: parent
            root: stubRoot
        }
    }

    Component {
        id: djiControlNullAppSettingsComp
        DJIControl {
            anchors.fill: parent
            root: stubRootNullAppSettings
        }
    }

    function _findRtmpUrlField(djiControl) {
        var f = findChild(djiControl, "rtmpUrlField")
        verify(f !== null,
               "rtmpUrlField must be findable by objectName "
               + "(Round 5 SHA 8a75023, DJIControl.qml:264)")
        return f
    }

    function _resetSettings(opts) {
        stubAppSettings.djiPreviewRouteStem = ("djiPreviewRouteStem" in opts)
            ? opts.djiPreviewRouteStem : ""
        stubPlatform.hotspotIPAddress = ("hotspotIPAddress" in opts)
            ? opts.hotspotIPAddress : ""
    }

    function _instantiate() {
        var d = createTemporaryObject(djiControlComp, tc)
        verify(d !== null, "DJIControl must instantiate")
        wait(50)
        return d
    }

    // ============================================================
    // T-5.1 — Empty stem → empty URL (regardless of IP)
    // ============================================================
    function test_T_5_1_empty_stem_yields_empty_url() {
        _resetSettings({ hotspotIPAddress: "192.0.2.42", djiPreviewRouteStem: "" })
        var dji = _instantiate()
        var f = _findRtmpUrlField(dji)
        wait(50)

        compare(f.text, "",
                "empty stem must yield empty URL")
        verify(f.text.indexOf("rtmp://") === -1,
               "no rtmp:// scheme may leak from empty stem")
        verify(f.text.indexOf("proxy/dji-osmo-pocket3") === -1,
               "legacy proxy/dji-osmo-pocket3 stem must NOT appear")
    }

    // ============================================================
    // T-5.2 — Single-segment stem → standard URL
    // ============================================================
    function test_T_5_2_single_segment_stem() {
        _resetSettings({ hotspotIPAddress: "192.0.2.42", djiPreviewRouteStem: "proxy/dji" })
        var dji = _instantiate()
        var f = _findRtmpUrlField(dji)
        wait(50)

        compare(f.text, "rtmp://192.0.2.42:1935/proxy/dji",
                "ip + stem must be composed correctly")
        verify(f.text.indexOf("//proxy") === -1,
               "no spurious double-slash before proxy")
        verify(f.text.lastIndexOf("proxy/dji") === f.text.length - "proxy/dji".length,
               "stem must be appended without modification (endsWith proxy/dji)")
    }

    // ============================================================
    // T-5.3 — Multi-segment stem passes through verbatim
    // ============================================================
    function test_T_5_3_multi_segment_pass_through() {
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "live/dji/cam1" })
        var dji = _instantiate()
        var f = _findRtmpUrlField(dji)
        wait(50)

        compare(f.text, "rtmp://192.0.2.42:1935/live/dji/cam1",
                "pass-through must preserve every segment")
        verify(f.text.indexOf("/live/dji/cam1") !== -1,
               "every segment present in URL")
        // rtmp:, "", "192.0.2.42:1935", "live", "dji", "cam1" → 6
        compare(f.text.split("/").length, 6,
                "no extra/missing slash in multi-segment URL")
    }

    // ============================================================
    // T-5.4 — Trailing-slash stem preserves trailing slash
    // ============================================================
    function test_T_5_4_trailing_slash_preserved() {
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "proxy/dji/" })
        var dji = _instantiate()
        var f = _findRtmpUrlField(dji)
        wait(50)

        compare(f.text, "rtmp://192.0.2.42:1935/proxy/dji/",
                "trailing slash must be preserved (user choice)")
        compare(f.text.charAt(f.text.length - 1), "/",
                "URL must end with a slash")
    }

    // ============================================================
    // T-5.5 — Pinned current pass-through contract: 5 boundary cases
    // (Path A per coordinator Dispute 3 ruling; Task #19 will decide
    // sanitize-vs-document-and-reject in a future commit and flip these
    // assertions).
    //
    // Sub-cases:
    //   A leading-slash, B trailing-slash (= T-5.4),
    //   C multi-segment (= T-5.3), D whitespace-only,
    //   E protocol-prefixed.
    // ============================================================
    function test_T_5_5_pinned_pass_through_5_boundary_cases() {
        var dji, f

        // -- Sub-case A: leading slash --
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "/proxy/dji" })
        dji = _instantiate()
        f = _findRtmpUrlField(dji)
        wait(50)
        compare(f.text, "rtmp://192.0.2.42:1935//proxy/dji",
                "Sub-case A (leading slash): pass-through preserves the "
                + "leading slash, producing observable double slash")
        verify(f.text.indexOf("//proxy") !== -1,
               "Sub-case A: no silent sanitization stripped the leading slash")

        // -- Sub-case B: trailing slash (mirrors T-5.4 by design) --
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "proxy/dji/" })
        dji = _instantiate()
        f = _findRtmpUrlField(dji)
        wait(50)
        compare(f.text, "rtmp://192.0.2.42:1935/proxy/dji/",
                "Sub-case B (trailing slash): pass-through preserves the "
                + "trailing slash")

        // -- Sub-case C: multi-segment (mirrors T-5.3) --
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "live/dji/cam1" })
        dji = _instantiate()
        f = _findRtmpUrlField(dji)
        wait(50)
        compare(f.text, "rtmp://192.0.2.42:1935/live/dji/cam1",
                "Sub-case C (multi-segment): every segment present")

        // -- Sub-case D: whitespace-only --
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "   " })
        dji = _instantiate()
        f = _findRtmpUrlField(dji)
        wait(50)
        compare(f.text, "rtmp://192.0.2.42:1935/   ",
                "Sub-case D (whitespace-only): no String.prototype.trim() "
                + "is applied; raw stem flows through")
        verify(f.text.charAt(f.text.length - 4) === "/"
               && f.text.charAt(f.text.length - 3) === " "
               && f.text.charAt(f.text.length - 2) === " "
               && f.text.charAt(f.text.length - 1) === " ",
               "Sub-case D: trailing 3 whitespace chars are preserved verbatim")

        // -- Sub-case E: protocol-prefixed --
        _resetSettings({ hotspotIPAddress: "192.0.2.42",
                          djiPreviewRouteStem: "rtmp://other/" })
        dji = _instantiate()
        f = _findRtmpUrlField(dji)
        wait(50)
        compare(f.text, "rtmp://192.0.2.42:1935/rtmp://other/",
                "Sub-case E (protocol-prefixed): pass-through produces a "
                + "malformed nonsense URL — no scheme-detection short-circuit")
        verify(f.text.indexOf("rtmp://192.0.2.42:1935/rtmp://") !== -1,
               "Sub-case E: no scheme-detection logic engaged")
    }

    // ============================================================
    // T-5.6 — IP unset → empty URL (regardless of stem)
    //
    // DJIController.localWlan1Ip is a C++ singleton READ-only property;
    // we cannot mutate it from QML. We assert in-test that the default
    // value at runtime is "" so the binding's `if (!ip)` branch
    // resolves to "" when both stubs are empty.
    // ============================================================
    function test_T_5_6_ip_unset_yields_empty_url() {
        _resetSettings({ hotspotIPAddress: "",
                          djiPreviewRouteStem: "proxy/dji" })

        // Test-environment invariant: DJIController.localWlan1Ip
        // (Q_PROPERTY READ on the C++ singleton, dji_controller.h:25)
        // MUST default to "" in the headless test env so the binding's
        // `if (!ip) ip = DJIController.localWlan1Ip;` fallback chain at
        // DJIControl.qml:275 yields "" when both stubs are empty. If
        // this invariant ever fails (harness change, build env exposes
        // Wi-Fi adapter, C++ default changes), the test below would
        // fail confusingly — the diagnostic on f.text would say
        // "no IP → no URL" but the actual cause would be the
        // localWlan1Ip fallback firing. Assert the invariant
        // explicitly so a future env-drift surfaces immediately at
        // the right callsite, not via misleading downstream-assertion
        // failure.
        // [T1: test-reviewer-1 R1 IF1 finding (Minor) + adjudication
        //  this session, high; T3: DJIControl.qml:275 fallback chain
        //  read this session, high]
        compare(DJIController.localWlan1Ip, "",
                "T-5.6 depends on localWlan1Ip defaulting to empty in "
                + "test env — if this fails, the test environment "
                + "leaks Wi-Fi adapter state into the binding fallback "
                + "chain at DJIControl.qml:275")

        var dji = _instantiate()
        var f = _findRtmpUrlField(dji)
        wait(50)

        compare(f.text, "",
                "no IP → no URL")
        verify(f.text.indexOf("undefined") === -1
               && f.text.indexOf("null") === -1,
               "no JS coercion artifacts in URL")
    }

    // ============================================================
    // T-5.7 — appSettings === null → empty URL (defensive guard)
    //
    // DJIControl.qml:276-278 reads
    //   djiControlPage.root.appSettings ? ... : ""
    // so a null appSettings short-circuits stem to "" → URL "".
    // ============================================================
    function test_T_5_7_null_appsettings_yields_empty_url() {
        stubPlatform.hotspotIPAddress = "192.0.2.42"
        var dji = createTemporaryObject(djiControlNullAppSettingsComp, tc)
        verify(dji !== null, "DJIControl must instantiate with null appSettings")
        wait(50)

        var f = _findRtmpUrlField(dji)

        compare(f.text, "",
                "null appSettings → empty URL via defensive ternary")
        // No QML runtime warning leaked from a null-deref. We can't
        // capture qInstallMessageHandler from QML, so we assert via a
        // proxy: tryCompare-style stability — re-read text after a
        // delay and confirm it is still "" (no late binding warning
        // mutated state).
        wait(100)
        compare(f.text, "",
                "URL must remain empty after settling — proxy for "
                + "no-warning runtime")
    }
}
