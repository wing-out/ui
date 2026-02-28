pragma Singleton
import QtQuick

QtObject {
    // Current theme name
    property string currentTheme: "dark"

    // Background
    property color background: "#0A0E1A"
    property color backgroundSecondary: "#121829"

    // Glass surfaces
    readonly property real glassOpacity: 0.08
    readonly property real glassBlur: 20
    readonly property int glassRadius: 16
    readonly property int glassBorder: 1
    property color glassBorderColor: Qt.rgba(1, 1, 1, 0.12)
    property color surfaceColor: Qt.rgba(1, 1, 1, 0.06)
    property color surfaceHover: Qt.rgba(1, 1, 1, 0.10)
    property color surfaceActive: Qt.rgba(1, 1, 1, 0.14)

    // Accent colors
    property color accentPrimary: "#7C4DFF"
    property color accentSecondary: "#00E5FF"
    property color accentGradientStart: "#7C4DFF"
    property color accentGradientEnd: "#00E5FF"

    // Text
    property color textPrimary: Qt.rgba(1, 1, 1, 0.95)
    property color textSecondary: Qt.rgba(1, 1, 1, 0.60)
    property color textTertiary: Qt.rgba(1, 1, 1, 0.38)

    // Status colors
    property color success: "#4CAF50"
    property color warning: "#FF9800"
    property color error: "#F44336"
    property color info: "#2196F3"

    // Platform colors
    readonly property color twitch: "#9146FF"
    readonly property color youtube: "#FF0000"
    readonly property color kick: "#53FC18"

    // Icon font (Material Symbols Outlined)
    readonly property string iconFont: "Material Symbols Outlined"

    // Typography
    readonly property int fontHuge: 28
    readonly property int fontLarge: 20
    readonly property int fontMedium: 14
    readonly property int fontSmall: 12
    readonly property int fontTiny: 10

    // Spacing
    readonly property int spacingTiny: 4
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 16
    readonly property int spacingLarge: 24
    readonly property int spacingHuge: 32

    // Dimensions
    readonly property int navMenuWidth: 260
    readonly property int metricTileHeight: 100
    readonly property int statusBadgeHeight: 32
    readonly property int buttonHeight: 48
    readonly property int inputHeight: 44

    // Animation
    readonly property int animFast: 150
    readonly property int animNormal: 250
    readonly property int animSlow: 400

    // Theme palettes
    readonly property var themes: ({
        "dark": {
            background: "#0A0E1A",
            backgroundSecondary: "#121829",
            glassBorderColor: Qt.rgba(1, 1, 1, 0.12),
            surfaceColor: Qt.rgba(1, 1, 1, 0.06),
            surfaceHover: Qt.rgba(1, 1, 1, 0.10),
            surfaceActive: Qt.rgba(1, 1, 1, 0.14),
            accentPrimary: "#7C4DFF",
            accentSecondary: "#00E5FF",
            accentGradientStart: "#7C4DFF",
            accentGradientEnd: "#00E5FF",
            textPrimary: Qt.rgba(1, 1, 1, 0.95),
            textSecondary: Qt.rgba(1, 1, 1, 0.60),
            textTertiary: Qt.rgba(1, 1, 1, 0.38),
            success: "#4CAF50",
            warning: "#FF9800",
            error: "#F44336",
            info: "#2196F3"
        },
        "light": {
            background: "#F5F5F7",
            backgroundSecondary: "#FFFFFF",
            glassBorderColor: Qt.rgba(0, 0, 0, 0.10),
            surfaceColor: Qt.rgba(0, 0, 0, 0.04),
            surfaceHover: Qt.rgba(0, 0, 0, 0.08),
            surfaceActive: Qt.rgba(0, 0, 0, 0.12),
            accentPrimary: "#6200EE",
            accentSecondary: "#0097A7",
            accentGradientStart: "#6200EE",
            accentGradientEnd: "#0097A7",
            textPrimary: Qt.rgba(0, 0, 0, 0.87),
            textSecondary: Qt.rgba(0, 0, 0, 0.54),
            textTertiary: Qt.rgba(0, 0, 0, 0.38),
            success: "#388E3C",
            warning: "#F57C00",
            error: "#D32F2F",
            info: "#1976D2"
        },
        "midnight": {
            background: "#0D1B2A",
            backgroundSecondary: "#1B2838",
            glassBorderColor: Qt.rgba(0.4, 0.6, 0.8, 0.15),
            surfaceColor: Qt.rgba(0.3, 0.5, 0.7, 0.08),
            surfaceHover: Qt.rgba(0.3, 0.5, 0.7, 0.12),
            surfaceActive: Qt.rgba(0.3, 0.5, 0.7, 0.18),
            accentPrimary: "#64B5F6",
            accentSecondary: "#4DD0E1",
            accentGradientStart: "#64B5F6",
            accentGradientEnd: "#4DD0E1",
            textPrimary: Qt.rgba(0.85, 0.92, 1.0, 0.95),
            textSecondary: Qt.rgba(0.7, 0.8, 0.9, 0.60),
            textTertiary: Qt.rgba(0.6, 0.7, 0.8, 0.40),
            success: "#66BB6A",
            warning: "#FFA726",
            error: "#EF5350",
            info: "#42A5F5"
        },
        "amoled": {
            background: "#000000",
            backgroundSecondary: "#0A0A0A",
            glassBorderColor: Qt.rgba(1, 1, 1, 0.08),
            surfaceColor: Qt.rgba(1, 1, 1, 0.04),
            surfaceHover: Qt.rgba(1, 1, 1, 0.08),
            surfaceActive: Qt.rgba(1, 1, 1, 0.12),
            accentPrimary: "#00E676",
            accentSecondary: "#00BFA5",
            accentGradientStart: "#00E676",
            accentGradientEnd: "#00BFA5",
            textPrimary: Qt.rgba(1, 1, 1, 1.0),
            textSecondary: Qt.rgba(1, 1, 1, 0.70),
            textTertiary: Qt.rgba(1, 1, 1, 0.40),
            success: "#00E676",
            warning: "#FFAB00",
            error: "#FF1744",
            info: "#00B0FF"
        },
        "wingout-dark": {
            background: "#1A1018",
            backgroundSecondary: "#241820",
            glassBorderColor: Qt.rgba(0.97, 0.58, 0.12, 0.15),
            surfaceColor: Qt.rgba(0.97, 0.58, 0.12, 0.06),
            surfaceHover: Qt.rgba(0.97, 0.58, 0.12, 0.10),
            surfaceActive: Qt.rgba(0.97, 0.58, 0.12, 0.16),
            accentPrimary: "#F7931E",
            accentSecondary: "#2D6CC4",
            accentGradientStart: "#F7931E",
            accentGradientEnd: "#E8447A",
            textPrimary: Qt.rgba(1, 1, 1, 0.95),
            textSecondary: Qt.rgba(1, 1, 1, 0.60),
            textTertiary: Qt.rgba(1, 1, 1, 0.38),
            success: "#4CAF50",
            warning: "#FFB74D",
            error: "#EF5350",
            info: "#2D6CC4"
        },
        "wingout-light": {
            background: "#FFF8F2",
            backgroundSecondary: "#FFFFFF",
            glassBorderColor: Qt.rgba(0.18, 0.42, 0.77, 0.12),
            surfaceColor: Qt.rgba(0.97, 0.58, 0.12, 0.06),
            surfaceHover: Qt.rgba(0.97, 0.58, 0.12, 0.10),
            surfaceActive: Qt.rgba(0.97, 0.58, 0.12, 0.16),
            accentPrimary: "#E07A0A",
            accentSecondary: "#2560B0",
            accentGradientStart: "#F7931E",
            accentGradientEnd: "#D63A6A",
            textPrimary: Qt.rgba(0, 0, 0, 0.87),
            textSecondary: Qt.rgba(0, 0, 0, 0.54),
            textTertiary: Qt.rgba(0, 0, 0, 0.38),
            success: "#388E3C",
            warning: "#E65100",
            error: "#C62828",
            info: "#2560B0"
        }
    })

    // Available theme names for UI
    readonly property var themeNames: ["dark", "light", "wingout-dark", "wingout-light", "midnight", "amoled"]
    readonly property var themeLabels: ["Dark", "Light", "WingOut Dark", "WingOut Light", "Midnight", "AMOLED"]

    function applyTheme(name) {
        var palette = themes[name]
        if (!palette) {
            console.warn("Unknown theme:", name)
            return
        }
        currentTheme = name
        background = palette.background
        backgroundSecondary = palette.backgroundSecondary
        glassBorderColor = palette.glassBorderColor
        surfaceColor = palette.surfaceColor
        surfaceHover = palette.surfaceHover
        surfaceActive = palette.surfaceActive
        accentPrimary = palette.accentPrimary
        accentSecondary = palette.accentSecondary
        accentGradientStart = palette.accentGradientStart
        accentGradientEnd = palette.accentGradientEnd
        textPrimary = palette.textPrimary
        textSecondary = palette.textSecondary
        textTertiary = palette.textTertiary
        success = palette.success
        warning = palette.warning
        error = palette.error
        info = palette.info
    }

    Component.onCompleted: applyTheme(currentTheme)

    // Utility functions
    function colorMix(c1: color, c2: color, ratio: real): color {
        return Qt.rgba(
            c1.r * (1 - ratio) + c2.r * ratio,
            c1.g * (1 - ratio) + c2.g * ratio,
            c1.b * (1 - ratio) + c2.b * ratio,
            c1.a * (1 - ratio) + c2.a * ratio
        )
    }

    function formatBandwidth(bitsPerSec: real): string {
        if (bitsPerSec >= 1000000) {
            return (bitsPerSec / 1000000).toFixed(1) + " Mbps"
        } else if (bitsPerSec >= 1000) {
            return (bitsPerSec / 1000).toFixed(0) + " kbps"
        }
        return bitsPerSec.toFixed(0) + " bps"
    }

    function formatDuration(seconds: real): string {
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        var s = Math.floor(seconds % 60)
        if (h > 0) {
            return h + ":" + String(m).padStart(2, '0') + ":" + String(s).padStart(2, '0')
        }
        return m + ":" + String(s).padStart(2, '0')
    }

    function formatLatency(microseconds: real): string {
        if (microseconds >= 1000000) {
            return (microseconds / 1000000).toFixed(2) + " s"
        } else if (microseconds >= 1000) {
            return (microseconds / 1000).toFixed(1) + " ms"
        }
        return microseconds.toFixed(0) + " µs"
    }

    function normalizeNumber(value, defaultVal) {
        if (value === undefined || value === null || isNaN(value)) return defaultVal
        return Number(value)
    }

    // Color coding functions for dashboard metrics
    // All use smooth gradients via colorMix between success/warning/error

    function fpsColor(fps: real): color {
        if (fps < 15) return error
        if (fps < 24) return colorMix(error, warning, (fps - 15) / 9)
        if (fps < 28) return colorMix(warning, success, (fps - 24) / 4)
        return success
    }

    function latencyColor(ms: real): color {
        if (ms < 100) return success
        if (ms < 400) return colorMix(success, warning, (ms - 100) / 300)
        if (ms < 1500) return colorMix(warning, error, (ms - 400) / 1100)
        return error
    }

    function bitrateColor(bps: real): color {
        if (bps < 50000) return error
        if (bps < 1000000) return colorMix(error, warning, (bps - 50000) / 950000)
        if (bps < 5000000) return colorMix(warning, success, (bps - 1000000) / 4000000)
        return success
    }

    function rssiColor(dBm: int): color {
        if (dBm > -50) return success
        if (dBm > -60) return colorMix(success, warning, (-50 - dBm) / 10)
        if (dBm > -70) return colorMix(warning, error, (-60 - dBm) / 10)
        return error
    }

    function pingColor(ms: real): color {
        if (ms < 20) return success
        if (ms < 100) return colorMix(success, warning, (ms - 20) / 80)
        if (ms < 1000) return colorMix(warning, error, (ms - 100) / 900)
        return error
    }

    function channelQualityColor(q: real): color {
        if (q < -33) return error
        if (q < 5) return colorMix(error, warning, (q + 33) / 38)
        if (q < 20) return colorMix(warning, success, (q - 5) / 15)
        return success
    }

    function temperatureColor(temp: real, sensorType: string): color {
        var warnThresh, critThresh
        if (sensorType === "battery") {
            warnThresh = 38; critThresh = 45
        } else if (sensorType === "cpu") {
            warnThresh = 70; critThresh = 90
        } else if (sensorType === "skin") {
            warnThresh = 35; critThresh = 42
        } else {
            warnThresh = 50; critThresh = 70
        }
        if (temp < warnThresh) return success
        if (temp < critThresh) return colorMix(warning, error, (temp - warnThresh) / (critThresh - warnThresh))
        return error
    }

    function cpuColor(util: real): color {
        if (util < 50) return success
        if (util < 80) return colorMix(success, warning, (util - 50) / 30)
        if (util < 95) return colorMix(warning, error, (util - 80) / 15)
        return error
    }

    function memColor(util: real): color {
        if (util < 60) return success
        if (util < 80) return colorMix(success, warning, (util - 60) / 20)
        if (util < 95) return colorMix(warning, error, (util - 80) / 15)
        return error
    }

    function playerLagColor(ms: real): color {
        if (ms < 500) return warning  // too low = risky
        if (ms < 1000) return colorMix(warning, success, (ms - 500) / 500)
        if (ms < 5000) return success
        if (ms < 10000) return colorMix(success, warning, (ms - 5000) / 5000)
        return error
    }

    function qualityColor(continuity: real): color {
        if (continuity > 0.99) return success
        if (continuity > 0.95) return colorMix(success, warning, (0.99 - continuity) / 0.04)
        if (continuity > 0.90) return colorMix(warning, error, (0.95 - continuity) / 0.05)
        return error
    }
}
