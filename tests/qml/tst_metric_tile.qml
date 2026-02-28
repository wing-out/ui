import QtQuick
import QtTest
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "MetricTile"
    when: windowShown
    width: 400
    height: 400

    Component {
        id: basicTile
        Components.MetricTile {
            width: 180
            title: "Bitrate"
            value: "5.2 Mbps"
            numericValue: 5200000
        }
    }

    function test_basic_properties() {
        var tile = createTemporaryObject(basicTile, testCase)
        verify(tile !== null)
        compare(tile.title, "Bitrate")
        compare(tile.value, "5.2 Mbps")
        compare(tile.numericValue, 5200000)
    }

    function test_default_unit() {
        var tile = createTemporaryObject(basicTile, testCase)
        compare(tile.unit, "")
    }

    function test_default_thresholds() {
        var tile = createTemporaryObject(basicTile, testCase)
        compare(tile.warningThreshold, -1)
        compare(tile.criticalThreshold, -1)
    }

    function test_height() {
        var tile = createTemporaryObject(basicTile, testCase)
        compare(tile.implicitHeight, WO.Theme.metricTileHeight)
    }

    // --- Color threshold tests ---

    Component {
        id: thresholdTile
        Components.MetricTile {
            width: 180
            title: "Latency"
            value: "50 ms"
            unit: "ms"
            warningThreshold: 100
            criticalThreshold: 500
        }
    }

    function test_normal_color() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 50
        var color = tile.computeColor()
        compare(color, WO.Theme.textPrimary)
    }

    function test_warning_color() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 150
        var color = tile.computeColor()
        compare(color, WO.Theme.warning)
    }

    function test_critical_color() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 600
        var color = tile.computeColor()
        compare(color, WO.Theme.error)
    }

    function test_exact_warning_boundary() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 100
        var color = tile.computeColor()
        compare(color, WO.Theme.warning)
    }

    function test_exact_critical_boundary() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 500
        var color = tile.computeColor()
        compare(color, WO.Theme.error)
    }

    function test_below_warning() {
        var tile = createTemporaryObject(thresholdTile, testCase)
        tile.numericValue = 99
        var color = tile.computeColor()
        compare(color, WO.Theme.textPrimary)
    }

    // --- Unit display ---

    Component {
        id: unitTile
        Components.MetricTile {
            width: 180
            title: "FPS"
            value: "30"
            unit: "fps"
            numericValue: 30
        }
    }

    function test_unit_property() {
        var tile = createTemporaryObject(unitTile, testCase)
        compare(tile.unit, "fps")
    }

    // --- Dynamic updates ---

    function test_dynamic_value_update() {
        var tile = createTemporaryObject(basicTile, testCase)
        tile.value = "10.0 Mbps"
        tile.numericValue = 10000000
        compare(tile.value, "10.0 Mbps")
        compare(tile.numericValue, 10000000)
    }

    // --- No thresholds (disabled) ---

    Component {
        id: noThresholdTile
        Components.MetricTile {
            width: 180
            title: "Ping"
            value: "50"
            numericValue: 9999
        }
    }

    function test_no_thresholds_always_primary() {
        var tile = createTemporaryObject(noThresholdTile, testCase)
        var color = tile.computeColor()
        compare(color, WO.Theme.textPrimary)
    }
}
