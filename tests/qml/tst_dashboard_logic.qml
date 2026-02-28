import QtQuick
import QtTest
import "../../qml" as WO

TestCase {
    id: testCase
    name: "DashboardLogic"
    when: windowShown
    width: 400
    height: 400

    // --- Theme utility function tests ---

    function test_formatBandwidth_bps() {
        compare(WO.Theme.formatBandwidth(500), "500 bps")
    }

    function test_formatBandwidth_kbps() {
        compare(WO.Theme.formatBandwidth(5000), "5 kbps")
    }

    function test_formatBandwidth_mbps() {
        compare(WO.Theme.formatBandwidth(5200000), "5.2 Mbps")
    }

    function test_formatBandwidth_zero() {
        compare(WO.Theme.formatBandwidth(0), "0 bps")
    }

    function test_formatBandwidth_boundary_kbps() {
        compare(WO.Theme.formatBandwidth(1000), "1 kbps")
    }

    function test_formatBandwidth_boundary_mbps() {
        compare(WO.Theme.formatBandwidth(1000000), "1.0 Mbps")
    }

    function test_formatLatency_microseconds() {
        compare(WO.Theme.formatLatency(500), "500 \u00B5s")
    }

    function test_formatLatency_milliseconds() {
        compare(WO.Theme.formatLatency(5000), "5.0 ms")
    }

    function test_formatLatency_seconds() {
        compare(WO.Theme.formatLatency(2500000), "2.50 s")
    }

    function test_formatLatency_zero() {
        compare(WO.Theme.formatLatency(0), "0 \u00B5s")
    }

    function test_formatLatency_boundary_ms() {
        compare(WO.Theme.formatLatency(1000), "1.0 ms")
    }

    function test_formatDuration_seconds_only() {
        compare(WO.Theme.formatDuration(45), "0:45")
    }

    function test_formatDuration_minutes_seconds() {
        compare(WO.Theme.formatDuration(125), "2:05")
    }

    function test_formatDuration_hours() {
        compare(WO.Theme.formatDuration(3661), "1:01:01")
    }

    function test_formatDuration_zero() {
        compare(WO.Theme.formatDuration(0), "0:00")
    }

    function test_normalizeNumber_valid() {
        compare(WO.Theme.normalizeNumber(42, 0), 42)
    }

    function test_normalizeNumber_undefined() {
        compare(WO.Theme.normalizeNumber(undefined, -1), -1)
    }

    function test_normalizeNumber_null() {
        compare(WO.Theme.normalizeNumber(null, 99), 99)
    }

    function test_normalizeNumber_nan() {
        compare(WO.Theme.normalizeNumber(NaN, 5), 5)
    }

    function test_normalizeNumber_string_number() {
        compare(WO.Theme.normalizeNumber("42", 0), 42)
    }

    function test_normalizeNumber_float() {
        compare(WO.Theme.normalizeNumber(3.14, 0), 3.14)
    }

    function test_normalizeNumber_zero() {
        compare(WO.Theme.normalizeNumber(0, 99), 0)
    }

    // --- Color mixing ---

    function test_colorMix_equal() {
        var result = WO.Theme.colorMix(Qt.rgba(1, 0, 0, 1), Qt.rgba(0, 0, 1, 1), 0.5)
        fuzzyCompare(result.r, 0.5, 0.01)
        fuzzyCompare(result.g, 0.0, 0.01)
        fuzzyCompare(result.b, 0.5, 0.01)
    }

    function test_colorMix_full_first() {
        var result = WO.Theme.colorMix(Qt.rgba(1, 0, 0, 1), Qt.rgba(0, 0, 1, 1), 0.0)
        fuzzyCompare(result.r, 1.0, 0.01)
        fuzzyCompare(result.b, 0.0, 0.01)
    }

    function test_colorMix_full_second() {
        var result = WO.Theme.colorMix(Qt.rgba(1, 0, 0, 1), Qt.rgba(0, 0, 1, 1), 1.0)
        fuzzyCompare(result.r, 0.0, 0.01)
        fuzzyCompare(result.b, 1.0, 0.01)
    }

    // --- Theme constants sanity checks ---

    function test_theme_background() {
        verify(WO.Theme.background !== undefined)
        compare(WO.Theme.background, Qt.color("#0A0E1A"))
    }

    function test_theme_accent() {
        compare(WO.Theme.accentPrimary, Qt.color("#7C4DFF"))
        compare(WO.Theme.accentSecondary, Qt.color("#00E5FF"))
    }

    function test_theme_platform_colors() {
        compare(WO.Theme.twitch, Qt.color("#9146FF"))
        compare(WO.Theme.youtube, Qt.color("#FF0000"))
        compare(WO.Theme.kick, Qt.color("#53FC18"))
    }

    function test_theme_spacing_hierarchy() {
        verify(WO.Theme.spacingTiny < WO.Theme.spacingSmall)
        verify(WO.Theme.spacingSmall < WO.Theme.spacingMedium)
        verify(WO.Theme.spacingMedium < WO.Theme.spacingLarge)
        verify(WO.Theme.spacingLarge < WO.Theme.spacingHuge)
    }

    function test_theme_font_hierarchy() {
        verify(WO.Theme.fontTiny < WO.Theme.fontSmall)
        verify(WO.Theme.fontSmall < WO.Theme.fontMedium)
        verify(WO.Theme.fontMedium < WO.Theme.fontLarge)
        verify(WO.Theme.fontLarge < WO.Theme.fontHuge)
    }

    function test_theme_animation_hierarchy() {
        verify(WO.Theme.animFast < WO.Theme.animNormal)
        verify(WO.Theme.animNormal < WO.Theme.animSlow)
    }

    // --- Dashboard metric computation logic ---

    function test_fps_computation_normal() {
        var num = 30; var den = 1
        var fps = den > 0 ? num / den : 0
        compare(fps, 30)
    }

    function test_fps_computation_fractional() {
        var num = 30000; var den = 1001
        var fps = den > 0 ? num / den : 0
        fuzzyCompare(fps, 29.97, 0.01)
    }

    function test_fps_computation_zero_den() {
        var num = 30; var den = 0
        var fps = den > 0 ? num / den : 0
        compare(fps, 0)
    }

    function test_continuity_percentage() {
        var continuity = 0.95
        var display = (continuity * 100).toFixed(1)
        compare(display, "95.0")
    }

    function test_latency_total() {
        var sending = 5000
        var transcoding = 3000
        var total = sending + transcoding
        compare(total, 8000)
    }

    // --- Stream uptime calculation ---

    function test_formatDuration_one_hour_exact() {
        compare(WO.Theme.formatDuration(3600), "1:00:00")
    }

    function test_formatDuration_multi_hour() {
        compare(WO.Theme.formatDuration(7384), "2:03:04")
    }

    function test_formatDuration_large_hours() {
        // 10 hours, 30 minutes, 15 seconds
        compare(WO.Theme.formatDuration(37815), "10:30:15")
    }

    function test_formatDuration_just_under_one_hour() {
        compare(WO.Theme.formatDuration(3599), "59:59")
    }

    function test_formatDuration_single_second() {
        compare(WO.Theme.formatDuration(1), "0:01")
    }

    // Stream uptime incrementing logic (simulated)
    property int testUptimeSeconds: 0
    property bool testStreamActive: false

    Timer {
        id: testUptimeTimer
        interval: 50 // fast for testing
        running: testCase.testStreamActive
        repeat: true
        onTriggered: testCase.testUptimeSeconds++
    }

    function test_uptime_increments_when_active() {
        testUptimeSeconds = 0
        testStreamActive = true
        wait(180)
        testStreamActive = false
        verify(testUptimeSeconds >= 2, "Uptime should have incremented at least twice, got " + testUptimeSeconds)
    }

    function test_uptime_stops_when_inactive() {
        testUptimeSeconds = 0
        testStreamActive = false
        wait(150)
        compare(testUptimeSeconds, 0, "Uptime should not increment when inactive")
    }

    // --- Viewer count display logic ---

    function test_viewer_count_total_all_platforms() {
        var twitch = 150
        var youtube = 200
        var kick = 50
        var total = twitch + youtube + kick
        compare(total, 400)
    }

    function test_viewer_count_total_zero() {
        var twitch = 0
        var youtube = 0
        var kick = 0
        var total = twitch + youtube + kick
        compare(total, 0)
    }

    function test_viewer_count_single_platform() {
        var twitch = 42
        var youtube = 0
        var kick = 0
        var total = twitch + youtube + kick
        compare(total, 42)
    }

    function test_viewer_badge_label_with_count() {
        var viewers = 150
        var label = "Twitch" + (viewers > 0 ? " (" + viewers + ")" : "")
        compare(label, "Twitch (150)")
    }

    function test_viewer_badge_label_no_viewers() {
        var viewers = 0
        var label = "Twitch" + (viewers > 0 ? " (" + viewers + ")" : "")
        compare(label, "Twitch")
    }

    function test_viewer_badge_active_with_viewers() {
        var viewers = 10
        verify(viewers > 0, "Badge should be active when viewers > 0")
    }

    function test_viewer_badge_inactive_no_viewers() {
        var viewers = 0
        verify(viewers === 0, "Badge should be inactive when viewers == 0")
    }

    // --- Signal strength mapping ---

    function test_signal_strength_display_valid() {
        var signal = -70
        var display = signal > 0 ? signal.toString() : "--"
        // signalStrength is negative dBm, so this tests the negative value handling
        compare(display, "--")
    }

    function test_signal_strength_positive_displayed() {
        // The dashboard checks signalStrength > 0 for display
        var signal = 70
        var display = signal > 0 ? signal.toString() : "--"
        compare(display, "70")
    }

    function test_signal_strength_abs_for_threshold() {
        // MetricTile numericValue uses Math.abs(signalStrength) for threshold comparison
        var signal = -70
        var numeric = Math.abs(signal)
        compare(numeric, 70)
    }

    function test_signal_strength_warning_threshold() {
        // Warning at 70, Critical at 85
        var signal = -75
        var numeric = Math.abs(signal)
        verify(numeric >= 70, "Signal " + signal + " should trigger warning threshold")
        verify(numeric < 85, "Signal " + signal + " should not trigger critical threshold")
    }

    function test_signal_strength_critical_threshold() {
        var signal = -90
        var numeric = Math.abs(signal)
        verify(numeric >= 85, "Signal " + signal + " should trigger critical threshold")
    }

    function test_signal_strength_good() {
        var signal = -50
        var numeric = Math.abs(signal)
        verify(numeric < 70, "Signal " + signal + " should be in good range")
    }

    // --- Diagnostics/metric display formatting ---

    function test_fps_display_with_value() {
        var fps = 29.97
        var display = fps > 0 ? fps.toFixed(1) : "--"
        compare(display, "30.0")
    }

    function test_fps_display_no_value() {
        var fps = 0
        var display = fps > 0 ? fps.toFixed(1) : "--"
        compare(display, "--")
    }

    function test_ping_display_with_value() {
        var rtt = 45
        var display = rtt > 0 ? rtt.toFixed(0) : "--"
        compare(display, "45")
    }

    function test_ping_display_no_value() {
        var rtt = 0
        var display = rtt > 0 ? rtt.toFixed(0) : "--"
        compare(display, "--")
    }

    function test_continuity_display_with_value() {
        var continuity = 0.987
        var display = continuity > 0 ? (continuity * 100).toFixed(1) : "--"
        compare(display, "98.7")
    }

    function test_continuity_inverse_for_threshold() {
        // numericValue uses (1 - continuity) * 100 for threshold comparison
        var continuity = 0.95
        var numeric = (1 - continuity) * 100
        fuzzyCompare(numeric, 5.0, 0.01)
    }
}
