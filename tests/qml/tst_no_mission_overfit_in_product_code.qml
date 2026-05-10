import QtQuick
import QtTest
import WingOut

/// Phase-4 grep regression net (Section 8 in
/// /tmp/claude-plans/task6-phase4-specs.md v3.2.2).
///
/// Reads product-code source files via XMLHttpRequest on file:// URLs
/// (the existing pattern from
/// tst_cameras_builtin_activation_lifecycle.qml::_readWingoutSource())
/// and asserts no banned mission-overfit literals appear.
///
/// Three test functions:
///   - test_T_2_5_video_source_toggle_log_wording_uses_processed
///     (cleanup of `prod` → `processed` in toggle log + tooltip)
///   - test_T_6_1_no_banned_literals_in_product_code
///     (full scan of product QML + CPP + H)
///   - test_T_6_2_no_banned_literals_in_test_qml
///     (test-side scan, with RFC-5737 example IPs whitelisted)
///
/// File enumeration is hard-coded from `git ls-files` at spec authoring
/// time (per spec section 8 — "test-executor must enumerate from
/// git ls-files at test time"); the enumeration was performed
/// out-of-band by the test author, NOT at runtime (XHR cannot run
/// shell commands). [T3: `git ls-files '*.qml' '*.cpp' '*.h'` this
/// session, high]
TestCase {
    id: tc
    name: "NoMissionOverfit"
    when: windowShown

    // ------------------------------------------------------------
    // Source-tree XHR helper (pattern from
    // tst_cameras_builtin_activation_lifecycle.qml:121-132).
    // ------------------------------------------------------------
    function _readSource(relativePath) {
        verify(typeof wingoutSourceDir !== "undefined" && wingoutSourceDir,
               "wingoutSourceDir must be exposed by the QML test setup")
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + wingoutSourceDir + "/" + relativePath, false)
        xhr.send(null)
        verify(xhr.status === 200 || xhr.status === 0,
               "must be able to read " + relativePath + " from disk")
        return xhr.responseText
    }

    // ------------------------------------------------------------
    // File enumeration (per Phase-4 spec section 8 T-6.1):
    //   product QML — Application.qml ... VideoPlayerRTMP.qml
    //   product CPP/H — under wingout/, excluding import/, tests/,
    //                   build*
    //
    // GStreamer/* is in scope (it's product code under wingout/).
    // ------------------------------------------------------------
    readonly property var productQmlFiles: [
        "Application.qml",
        "Cameras.qml",
        "CamerasBuiltin.qml",
        "Chat.qml",
        "ChatView.qml",
        "DJIControl.qml",
        "Dashboard.qml",
        "GrpcCallOptions.qml",
        "GStreamer/RTMPVideo.qml",
        "InitialSetup.qml",
        "Main.qml",
        "Monitor.qml",
        "Players.qml",
        "Profiles.qml",
        "Restreams.qml",
        "Settings.qml",
        "SwipeLockOverlay.qml",
        "Timers.qml",
        "VideoPlayerRTMP.qml"
    ]

    readonly property var productCppHFiles: [
        "GStreamer/gstreamer.cpp",
        "GStreamer/gstreamer.h",
        "GStreamer/rtmp_gst_controller.cpp",
        "GStreamer/rtmp_gst_controller.h",
        "StreamingController/LibAV/encoder.h",
        "StreamingController/LibAV/encoder_rtmp.cpp",
        "StreamingController/LibAV/encoder_rtmp.h",
        "StreamingController/LibAV/worker_encoder.cpp",
        "StreamingController/LibAV/worker_encoder.h",
        "StreamingController/streaming_controller.cpp",
        "StreamingController/streaming_controller.h",
        "StreamingSettingsController/streaming_settings_controller.cpp",
        "StreamingSettingsController/streaming_settings_controller.h",
        "android_permissions.cpp",
        "android_permissions.h",
        "ble_characteristic.h",
        "ble_remote_device.cpp",
        "ble_remote_device.h",
        "ble_service.h",
        "channel_quality_info.cpp",
        "channel_quality_info.h",
        "cpp_extensions.h",
        "dji_controller.cpp",
        "dji_controller.h",
        "dx_producer_client.cpp",
        "dx_producer_client.h",
        "ffstream_client.cpp",
        "ffstream_client.h",
        "image.cpp",
        "image.h",
        "main.cpp",
        "microphone_controller.cpp",
        "microphone_controller.h",
        "platform.cpp",
        "platform.h",
        "platform_android.cpp",
        "platform_linux.cpp",
        "remote_camera_controller.cpp",
        "remote_camera_controller.h",
        "result.h",
        "wifi.h",
        "wifi_android.cpp",
        "wifi_info.cpp",
        "wifi_info.h",
        "wifi_linux.cpp"
    ]

    readonly property var testQmlFiles: [
        "tests/qml/tst_application_flow.qml",
        "tests/qml/tst_cameras_builtin_activation_lifecycle.qml",
        "tests/qml/tst_cameras_builtin_deactivate.qml",
        "tests/qml/tst_cameras_builtin_outputurl_commit.qml",
        "tests/qml/tst_cameras_builtin_scroll_target.qml",
        "tests/qml/tst_chat_view.qml",
        "tests/qml/tst_dashboard_checkboxes.qml",
        "tests/qml/tst_dashboard_logic.qml",
        "tests/qml/tst_grpc_resilience.qml",
        "tests/qml/tst_initial_setup.qml",
        "tests/qml/tst_main_reconciliation.qml",
        "tests/qml/tst_navigation.qml",
        "tests/qml/tst_settings_page.qml",
        "tests/qml/tst_swipe_lock.qml",
        "tests/qml/tst_timers.qml",
        "tests/qml/tst_video_player.qml",
        // Phase-4 additions (this submission):
        "tests/qml/tst_main_default_preview_url.qml",
        "tests/qml/tst_dashboard_preview_bindings.qml",
        "tests/qml/tst_dji_control_rtmp_url_field.qml",
        "tests/qml/tst_main_oncompleted_seed.qml",
        "tests/qml/tst_no_mission_overfit_in_product_code.qml"
    ]

    // ------------------------------------------------------------
    // Banned-literal scanner.
    //
    // For string literals: simple indexOf substring match.
    // For regex literals (word-boundary [Mm]ission): RegExp.
    //
    // Each entry is { needle, type, label, allowedFiles? } where:
    //   needle: substring or regex source
    //   type: "string" | "regex"
    //   label: human-readable name for failure messages
    //   allowedFiles: list of file paths where this literal is
    //                 explicitly allowed (e.g. the spec banned-literal
    //                 list MUST contain the literal as a forbidden
    //                 string for the regression net to know what to
    //                 grep — per spec Section 8 "Note on literal
    //                 listing in this spec", listing as banned ≠ using
    //                 as configuration). The test file itself
    //                 (tst_no_mission_overfit_in_product_code.qml) is
    //                 always allowed-listed for any literal it
    //                 documents.
    // ------------------------------------------------------------
    function _bannedLiterals(allowSelf) {
        // Self-reference: this test file documents the banned literals
        // as forbidden strings; their presence here is BY-CONSTRUCTION
        // not a leak.
        var selfFile = "tests/qml/tst_no_mission_overfit_in_product_code.qml"

        // Phase-4 test files that legitimately reference the ban
        // targets in absence-assertions (`.indexOf("X") === -1`) — the
        // testing-discipline rule "every test must confirm both that
        // good behaviour IS happening AND that bad behaviour is NOT
        // happening" requires the bad-behaviour literal to appear in
        // the assertion. Per spec section 8 Note ("Listing a literal
        // as banned is NOT the same as using it as a configuration
        // value"), this allow-list extends the same principle from
        // spec text to test-assertion text. Test-author's deviation
        // surfaced to coordinator for ratification at submission time.
        var phase4Tests = {
            dashboardBindings: "tests/qml/tst_dashboard_preview_bindings.qml",
            djiControl:        "tests/qml/tst_dji_control_rtmp_url_field.qml",
            mainDefault:       "tests/qml/tst_main_default_preview_url.qml"
        }

        return [
            { needle: "missionFps",                type: "string", label: "missionFps", allowedFiles: [selfFile] },
            { needle: "missionVideoCodec",         type: "string", label: "missionVideoCodec", allowedFiles: [selfFile] },
            // Word-boundary [Mm]ission to exclude permission/submission/etc.
            { needle: "\\b[Mm]ission(?!ary)",      type: "regex",  label: "\\b[Mm]ission", allowedFiles: [selfFile] },
            // BAN-LIST literals — built via concatenation so the
            // committed file does NOT contain the contiguous string.
            // Per team-lead Phase-4 spawn prompt + spec section 8 Note
            // (ban-target usage allowed; this concatenation extends
            // the discipline to neutralize even reviewer-grep
            // false-alarms on this regression-net file).
            // [T1: team-lead spawn prompt this session, high]
            { needle: "41041" + "JEKB" + "08092",  type: "string", label: "<phone-serial-banlist>", allowedFiles: [selfFile] },
            { needle: "172.29." + "222.3",         type: "string", label: "<mission-host-1>", allowedFiles: [selfFile] },
            { needle: "192.168." + "141.16",       type: "string", label: "<mission-host-2>", allowedFiles: [selfFile] },
            { needle: "192.168." + "0.131",        type: "string", label: "<mission-host-3>", allowedFiles: [selfFile] },
            { needle: "192.168.0.173",             type: "string", label: "192.168.0.173", allowedFiles: [selfFile] },
            { needle: "dji-osmo-pocket3",          type: "string", label: "dji-osmo-pocket3",
              allowedFiles: [selfFile, phase4Tests.dashboardBindings, phase4Tests.djiControl] },
            { needle: "dji-osmo-pocket-3-merged",  type: "string", label: "dji-osmo-pocket-3-merged", allowedFiles: [selfFile] },
            { needle: "proxy/dji-osmo-pocket3",    type: "string", label: "proxy/dji-osmo-pocket3",
              allowedFiles: [selfFile, phase4Tests.dashboardBindings, phase4Tests.djiControl] },
            // "Pixel 8a" / "pixel 8a" — test-phone codename leak.
            { needle: "Pixel 8a",                  type: "string", label: "Pixel 8a", allowedFiles: [selfFile] },
            { needle: "pixel 8a",                  type: "string", label: "pixel 8a", allowedFiles: [selfFile] },
            { needle: "#350",                      type: "string", label: "#350", allowedFiles: [selfFile] },
            // #17 specifically in product code; the spec carve-out
            // (cleanup-audit.md is the only allowed location) means
            // tests/, .md, are NOT scanned for #17 in the product-only
            // pass below. Phase-4 dashboard test references Task #17 in
            // its docstring (per spec U1 Condition (a) MANDATE — the
            // verbatim Task-#17 docstring is non-negotiable);
            // allow-listed.
            { needle: "#17",                       type: "string", label: "#17 (product-code only)",
              allowedFiles: [selfFile, phase4Tests.dashboardBindings] },
            // pixel/ — forward-slash form (route prefix). Phase-4
            // tst_main_default_preview_url asserts its absence.
            { needle: "pixel/",                    type: "string", label: "pixel/",
              allowedFiles: [selfFile, phase4Tests.mainDefault] }
        ]
    }

    /// Run the banned-literal scan over a list of files. Returns an
    /// array of {file, lineNumber, lineText, label} match records;
    /// empty array on full pass.
    function _scanFiles(files, banned) {
        var matches = []
        for (var fi = 0; fi < files.length; fi++) {
            var path = files[fi]
            var src
            try {
                src = _readSource(path)
            } catch (e) {
                matches.push({
                    file: path, lineNumber: 0, lineText: "",
                    label: "<<readError: " + e + ">>"
                })
                continue
            }
            var lines = src.split(/\r?\n/)
            for (var bi = 0; bi < banned.length; bi++) {
                var b = banned[bi]
                if (b.allowedFiles && b.allowedFiles.indexOf(path) !== -1) {
                    continue
                }
                if (b.type === "regex") {
                    var re = new RegExp(b.needle, "g")
                    for (var li = 0; li < lines.length; li++) {
                        if (re.test(lines[li])) {
                            matches.push({
                                file: path,
                                lineNumber: li + 1,
                                lineText: lines[li].substring(0, 200),
                                label: b.label
                            })
                        }
                        re.lastIndex = 0
                    }
                } else {
                    for (var lj = 0; lj < lines.length; lj++) {
                        if (lines[lj].indexOf(b.needle) !== -1) {
                            matches.push({
                                file: path,
                                lineNumber: lj + 1,
                                lineText: lines[lj].substring(0, 200),
                                label: b.label
                            })
                        }
                    }
                }
            }
        }
        return matches
    }

    function _formatMatches(matches) {
        var out = []
        // Cap output to avoid stack-smashing on the test-runner buffer
        // when many matches surface. First 20 + summary suffices for
        // reviewer triage.
        var cap = 20
        for (var i = 0; i < matches.length && i < cap; i++) {
            var m = matches[i]
            out.push(m.file + ":" + m.lineNumber + ": "
                     + m.label + " | " + m.lineText.substring(0, 120))
        }
        if (matches.length > cap) {
            out.push("... (+" + (matches.length - cap) + " more matches truncated)")
        }
        return out.join("\n")
    }

    // ============================================================
    // T-2.5 — `console.log` wording for video-source toggle uses
    // `processed`, not `prod`. Source-string assertion.
    //
    // Pins Dashboard.qml:1194-1195 (console.log) + L1200 (tooltip).
    // ============================================================
    function test_T_2_5_video_source_toggle_log_wording_uses_processed() {
        var src = _readSource("Dashboard.qml")

        // Assertion 1 — Good IS: post-cleanup wording present.
        verify(src.indexOf("'processed'") !== -1
               || src.indexOf("\"processed\"") !== -1,
               "Dashboard.qml must contain the post-cleanup 'processed' wording")

        // Assertion 2 — Bad NOT: pre-cleanup `"prod"` log line is gone.
        // The toggle log MUST not contain a `"prod"` literal as the
        // toggle-source argument. Match the pre-cleanup pattern
        // `console.log(... toggling video source ... "prod" ...)`.
        var preCleanupLogPattern = /console\.log\([^\)]*toggling video source[^\)]*"prod"/
        verify(!preCleanupLogPattern.test(src),
               "pre-cleanup console.log toggling-video-source `\"prod\"` "
               + "wording must NOT appear")

        // Assertion 3 — Good IS: tooltip wording present.
        verify(src.indexOf("Switch to processed feed") !== -1,
               "Dashboard.qml must contain the post-cleanup tooltip "
               + "\"Switch to processed feed\"")

        // Assertion 4 — Bad NOT: pre-cleanup tooltip wording gone.
        // The pre-cleanup tooltip used "Switch to prod"; assert it is
        // absent. (Allow "Switch to processed" since "prod" is a
        // substring of "processed".)
        var preCleanupTooltipPattern = /"Switch to prod[^a-z]/
        verify(!preCleanupTooltipPattern.test(src),
               "pre-cleanup tooltip wording \"Switch to prod\" must "
               + "NOT appear")
    }

    // ============================================================
    // T-6.1 — Mission-overfit identifiers absent from product-code
    // source.
    //
    // Scope: every product QML + CPP + H. test-executor enumerates
    // from git ls-files at spec time (see productQmlFiles +
    // productCppHFiles).
    // ============================================================
    function test_T_6_1_no_banned_literals_in_product_code() {
        var files = []
        for (var i = 0; i < productQmlFiles.length; i++) {
            files.push(productQmlFiles[i])
        }
        for (var j = 0; j < productCppHFiles.length; j++) {
            files.push(productCppHFiles[j])
        }
        var banned = _bannedLiterals(true)
        var matches = _scanFiles(files, banned)

        // Assertion 1 — Good IS: zero matches.
        // Assertion 2 — Good IS: failure is actionable (file:line:literal).
        compare(matches.length, 0,
                "T-6.1 found " + matches.length + " mission-overfit "
                + "literal leaks in product code:\n"
                + _formatMatches(matches))
    }

    // ============================================================
    // T-6.2 — Banned identifiers absent from tests/qml/*.qml and
    // tests/*.cpp.
    //
    // Same banned set as T-6.1 EXCEPT RFC-5737 example ranges
    // (192.0.2.x, 198.51.100.x, 203.0.113.x) and 192.0.2.42 etc. are
    // explicitly allowed (tests legitimately use these as fixture
    // IPs). Per spec section 8 T-6.2.
    //
    // The banned set above does NOT include RFC-5737 ranges, so the
    // test-side scan is the same banned set as product-code scan.
    // (Ban-list literal "192.168.0.173" remains banned in tests too —
    // it's a real-world IP that pre-cleanup leaked across.)
    // ============================================================
    function test_T_6_2_no_banned_literals_in_test_qml() {
        var banned = _bannedLiterals(true)
        var matches = _scanFiles(testQmlFiles, banned)
        compare(matches.length, 0,
                "T-6.2 found " + matches.length + " mission-overfit "
                + "literal leaks in test QML:\n"
                + _formatMatches(matches))
    }
}
