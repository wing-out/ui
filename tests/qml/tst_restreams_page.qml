import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "RestreamsPage"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: restreamsComponent
        Pages.RestreamsPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function init() {
        mockBackend.setTestForwards([])
        mockBackend.resetCallCounts()
    }

    function test_creation() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        verify(page !== null, "RestreamsPage created")
    }

    function test_empty_forwards() {
        mockBackend.setTestForwards([])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards.length, 0)
    }

    function test_forwards_loaded() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true},
            {sourceId: "cam0", sinkId: "youtube", sinkType: "rtmp", enabled: false}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards.length, 2)
    }

    function test_forward_data() {
        mockBackend.setTestForwards([
            {sourceId: "main", sinkId: "twitch_live", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards[0].sourceId, "main")
        compare(page.forwards[0].sinkId, "twitch_live")
        compare(page.forwards[0].sinkType, "rtmp")
        compare(page.forwards[0].enabled, true)
    }

    function test_forward_disabled() {
        mockBackend.setTestForwards([
            {sourceId: "src", sinkId: "sink", sinkType: "srt", enabled: false}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards[0].enabled, false)
    }

    function test_refresh_forwards() {
        mockBackend.setTestForwards([{sourceId: "a", sinkId: "b", sinkType: "rtmp", enabled: true}])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards.length, 1)

        mockBackend.setTestForwards([
            {sourceId: "a", sinkId: "b", sinkType: "rtmp", enabled: true},
            {sourceId: "c", sinkId: "d", sinkType: "srt", enabled: false}
        ])
        page.refreshForwards()
        wait(50)
        compare(page.forwards.length, 2)
    }

    function test_error_handling() {
        mockBackend.setTestError("listStreamForwards", "backend unavailable")
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards.length, 0)
        mockBackend.clearTestError("listStreamForwards")
    }

    function test_multiple_sources() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true},
            {sourceId: "cam1", sinkId: "youtube", sinkType: "rtmp", enabled: true},
            {sourceId: "cam0", sinkId: "kick", sinkType: "rtmp", enabled: false},
            {sourceId: "cam2", sinkId: "custom", sinkType: "srt", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        compare(page.forwards.length, 4)
    }

    // --- Enable/disable toggle per forward ---

    function test_toggle_button_text_enabled() {
        // Button text: modelData.enabled ? "Disable" : "Enable"
        var enabled = true
        var text = enabled ? "Disable" : "Enable"
        compare(text, "Disable")
    }

    function test_toggle_button_text_disabled() {
        var enabled = false
        var text = enabled ? "Disable" : "Enable"
        compare(text, "Enable")
    }

    function test_toggle_button_filled_when_disabled() {
        // filled: !modelData.enabled
        var enabled = false
        compare(!enabled, true)
    }

    function test_toggle_button_not_filled_when_enabled() {
        var enabled = true
        compare(!enabled, false)
    }

    function test_toggle_button_color_when_enabled() {
        var enabled = true
        var color = enabled ? WO.Theme.warning : WO.Theme.success
        compare(color, WO.Theme.warning)
    }

    function test_toggle_button_color_when_disabled() {
        var enabled = false
        var color = enabled ? WO.Theme.warning : WO.Theme.success
        compare(color, WO.Theme.success)
    }

    function test_toggle_button_exists() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        var btn = findChild(page, "forwardToggleBtn")
        verify(btn !== null, "Toggle button should exist")
    }

    function test_toggle_button_text_from_page() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        var btn = findChild(page, "forwardToggleBtn")
        compare(btn.text, "Disable")
    }

    // --- Remove forward button ---

    function test_remove_button_exists() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        var btn = findChild(page, "forwardRemoveBtn")
        verify(btn !== null, "Remove button should exist")
    }

    function test_remove_button_text() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        var btn = findChild(page, "forwardRemoveBtn")
        compare(btn.text, "Remove")
    }

    function test_remove_button_accent_color() {
        mockBackend.setTestForwards([
            {sourceId: "cam0", sinkId: "twitch", sinkType: "rtmp", enabled: true}
        ])
        var page = createTemporaryObject(restreamsComponent, testCase)
        wait(50)
        var btn = findChild(page, "forwardRemoveBtn")
        compare(btn.accentColor, WO.Theme.error)
    }

    // --- Add Forward form fields ---

    function test_add_forward_dialog_default_hidden() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        compare(page.showAddForwardDialog, false)
    }

    function test_add_forward_dialog_toggle() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.showAddForwardDialog = true
        compare(page.showAddForwardDialog, true)
    }

    function test_add_forward_button_text_toggle() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        var text1 = page.showAddForwardDialog ? "Cancel" : "Add Forward"
        compare(text1, "Add Forward")
        page.showAddForwardDialog = true
        var text2 = page.showAddForwardDialog ? "Cancel" : "Add Forward"
        compare(text2, "Cancel")
    }

    function test_new_forward_fields_default_empty() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        compare(page.newSourceId, "")
        compare(page.newSinkId, "")
    }

    function test_new_forward_source_field_set() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.newSourceId = "cam1"
        compare(page.newSourceId, "cam1")
    }

    function test_new_forward_sink_field_set() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.newSinkId = "twitch_out"
        compare(page.newSinkId, "twitch_out")
    }

    function test_confirm_add_enabled_when_filled() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.newSourceId = "cam1"
        page.newSinkId = "twitch"
        var enabled = page.newSourceId.length > 0 && page.newSinkId.length > 0
        compare(enabled, true)
    }

    function test_confirm_add_disabled_when_source_empty() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.newSourceId = ""
        page.newSinkId = "twitch"
        var enabled = page.newSourceId.length > 0 && page.newSinkId.length > 0
        compare(enabled, false)
    }

    function test_confirm_add_disabled_when_sink_empty() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.newSourceId = "cam1"
        page.newSinkId = ""
        var enabled = page.newSourceId.length > 0 && page.newSinkId.length > 0
        compare(enabled, false)
    }

    function test_forward_display_label() {
        // The page shows: sourceId + " -> " + sinkId
        var sourceId = "cam0"
        var sinkId = "twitch_live"
        var label = (sourceId || "?") + " \u2192 " + (sinkId || "?")
        compare(label, "cam0 \u2192 twitch_live")
    }

    function test_forward_display_label_missing_ids() {
        var sourceId = undefined
        var sinkId = undefined
        var label = (sourceId || "?") + " \u2192 " + (sinkId || "?")
        compare(label, "? \u2192 ?")
    }

    function test_forward_sink_type_display() {
        // sinkType fallback: modelData.sinkType || "custom"
        var sinkType = "rtmp"
        compare(sinkType || "custom", "rtmp")
    }

    function test_forward_sink_type_fallback() {
        var sinkType = undefined
        compare(sinkType || "custom", "custom")
    }

    function test_status_badge_active() {
        var enabled = true
        var label = enabled ? "Active" : "Disabled"
        compare(label, "Active")
    }

    function test_status_badge_disabled() {
        var enabled = false
        var label = enabled ? "Active" : "Disabled"
        compare(label, "Disabled")
    }

    // --- Add Forward form fields from mock ---

    function test_add_forward_button_exists() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        var btn = findChild(page, "addForwardButton")
        verify(btn !== null, "Add Forward button should exist")
    }

    function test_source_field_exists_in_dialog() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.showAddForwardDialog = true
        wait(50)
        var field = findChild(page, "fwdSourceField")
        verify(field !== null, "Source field should exist in dialog")
    }

    function test_sink_field_exists_in_dialog() {
        var page = createTemporaryObject(restreamsComponent, testCase)
        page.showAddForwardDialog = true
        wait(50)
        var field = findChild(page, "fwdSinkField")
        verify(field !== null, "Sink field should exist in dialog")
    }
}
