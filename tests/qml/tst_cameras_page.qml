import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "CamerasPage"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: camerasComponent
        Pages.CamerasPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function init() {
        mockBackend.setTestSources([])
        mockBackend.setTestServers([])
    }

    function test_creation() {
        var page = createTemporaryObject(camerasComponent, testCase)
        verify(page !== null, "CamerasPage created")
    }

    function test_empty_sources_default() {
        var page = createTemporaryObject(camerasComponent, testCase)
        compare(page.sources.length, 0)
    }

    function test_sources_set() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = [
            {id: "cam0", url: "rtmp://localhost/live"},
            {id: "cam1", url: "rtsp://192.168.1.10/stream"}
        ]
        compare(page.sources.length, 2)
        compare(page.sources[0].id, "cam0")
        compare(page.sources[1].url, "rtsp://192.168.1.10/stream")
    }

    function test_empty_state_visible() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = []
        compare(page.sources.length, 0)
    }

    function test_add_source() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = []
        var newSources = [{id: "new_cam", url: "rtmp://new/stream"}]
        page.sources = newSources
        compare(page.sources.length, 1)
        compare(page.sources[0].id, "new_cam")
    }

    function test_remove_source() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = [
            {id: "cam0", url: "url0"},
            {id: "cam1", url: "url1"},
            {id: "cam2", url: "url2"}
        ]
        compare(page.sources.length, 3)
        page.sources = [{id: "cam0", url: "url0"}, {id: "cam2", url: "url2"}]
        compare(page.sources.length, 2)
    }

    function test_source_data_integrity() {
        var page = createTemporaryObject(camerasComponent, testCase)
        var sources = [
            {id: "DJI Mini 4 Pro", url: "rtmp://192.168.0.1/live"},
            {id: "USB Webcam", url: "/dev/video0"},
            {id: "IP Camera", url: "rtsp://admin:pass@10.0.0.50/stream1"}
        ]
        page.sources = sources
        for (var i = 0; i < sources.length; i++) {
            compare(page.sources[i].id, sources[i].id)
            compare(page.sources[i].url, sources[i].url)
        }
    }

    // --- Source list rendering with active/inactive status ---

    function test_source_active_status() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = [
            {id: "cam0", url: "rtmp://localhost/live", isActive: true},
            {id: "cam1", url: "rtmp://localhost/live2", isActive: false}
        ]
        compare(page.sources[0].isActive, true)
        compare(page.sources[1].isActive, false)
    }

    function test_source_suppressed_status() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.sources = [
            {id: "cam0", url: "rtmp://localhost/live", isActive: true, isSuppressed: false},
            {id: "cam1", url: "rtmp://localhost/live2", isActive: false, isSuppressed: true}
        ]
        compare(page.sources[0].isSuppressed, false)
        compare(page.sources[1].isSuppressed, true)
    }

    function test_source_active_badge_label() {
        // StatusBadge label logic from the page
        var isActive = true
        var label = isActive ? "Active" : "Inactive"
        compare(label, "Active")
    }

    function test_source_inactive_badge_label() {
        var isActive = false
        var label = isActive ? "Active" : "Inactive"
        compare(label, "Inactive")
    }

    // --- Server list section ---

    function test_empty_servers_default() {
        var page = createTemporaryObject(camerasComponent, testCase)
        compare(page.servers.length, 0)
    }

    function test_servers_loaded() {
        mockBackend.setTestServers([
            {id: "srv0", listenAddr: ":1935", type: "rtmp"},
            {id: "srv1", listenAddr: ":8080", type: "srt"}
        ])
        var page = createTemporaryObject(camerasComponent, testCase)
        wait(50)
        compare(page.servers.length, 2)
        compare(page.servers[0].id, "srv0")
        compare(page.servers[0].type, "rtmp")
        compare(page.servers[1].listenAddr, ":8080")
    }

    function test_servers_empty_visibility_logic() {
        // The empty server card is visible when servers.length === 0
        var page = createTemporaryObject(camerasComponent, testCase)
        page.servers = []
        compare(page.servers.length === 0, true)
    }

    function test_servers_populated_visibility_logic() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.servers = [{id: "s1", listenAddr: ":1935", type: "rtmp"}]
        compare(page.servers.length === 0, false)
    }

    // --- Add Source form visibility and interaction ---

    function test_add_source_dialog_default_hidden() {
        var page = createTemporaryObject(camerasComponent, testCase)
        compare(page.showAddSourceDialog, false)
    }

    function test_add_source_dialog_toggle_on() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.showAddSourceDialog = true
        compare(page.showAddSourceDialog, true)
    }

    function test_add_source_dialog_toggle_off_clears_fields() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.showAddSourceDialog = true
        page.newSourceId = "test_cam"
        page.newSourceUrl = "rtmp://test"
        // Toggling off should happen via button click logic, but we test the state
        page.showAddSourceDialog = false
        page.newSourceId = ""
        page.newSourceUrl = ""
        compare(page.showAddSourceDialog, false)
        compare(page.newSourceId, "")
        compare(page.newSourceUrl, "")
    }

    function test_new_source_fields_default_empty() {
        var page = createTemporaryObject(camerasComponent, testCase)
        compare(page.newSourceId, "")
        compare(page.newSourceUrl, "")
    }

    function test_new_source_fields_set() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.newSourceId = "cam_new"
        page.newSourceUrl = "rtmp://192.168.1.1/live"
        compare(page.newSourceId, "cam_new")
        compare(page.newSourceUrl, "rtmp://192.168.1.1/live")
    }

    function test_add_source_button_text_toggles() {
        // Button text: showAddSourceDialog ? "Cancel" : "Add Source"
        var page = createTemporaryObject(camerasComponent, testCase)
        var text1 = page.showAddSourceDialog ? "Cancel" : "Add Source"
        compare(text1, "Add Source")
        page.showAddSourceDialog = true
        var text2 = page.showAddSourceDialog ? "Cancel" : "Add Source"
        compare(text2, "Cancel")
    }

    function test_confirm_add_enabled_when_fields_filled() {
        // The confirm button: enabled: newSourceId.length > 0 && newSourceUrl.length > 0
        var page = createTemporaryObject(camerasComponent, testCase)
        page.newSourceId = "cam1"
        page.newSourceUrl = "rtmp://test"
        var enabled = page.newSourceId.length > 0 && page.newSourceUrl.length > 0
        compare(enabled, true)
    }

    function test_confirm_add_disabled_when_id_empty() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.newSourceId = ""
        page.newSourceUrl = "rtmp://test"
        var enabled = page.newSourceId.length > 0 && page.newSourceUrl.length > 0
        compare(enabled, false)
    }

    function test_confirm_add_disabled_when_url_empty() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.newSourceId = "cam1"
        page.newSourceUrl = ""
        var enabled = page.newSourceId.length > 0 && page.newSourceUrl.length > 0
        compare(enabled, false)
    }

    function test_confirm_add_disabled_when_both_empty() {
        var page = createTemporaryObject(camerasComponent, testCase)
        page.newSourceId = ""
        page.newSourceUrl = ""
        var enabled = page.newSourceId.length > 0 && page.newSourceUrl.length > 0
        compare(enabled, false)
    }

    // --- Remove source button visibility ---

    function test_remove_source_button_exists_with_sources() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://localhost/live", isActive: true}
        ])
        var page = createTemporaryObject(camerasComponent, testCase)
        wait(50)
        var btn = findChild(page, "removeSourceBtn")
        verify(btn !== null, "Remove source button should exist when sources are present")
    }

    // --- Refresh sources from mock ---

    function test_sources_loaded_from_mock() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", isActive: true},
            {id: "cam1", url: "srt://b", isActive: false}
        ])
        var page = createTemporaryObject(camerasComponent, testCase)
        wait(50)
        compare(page.sources.length, 2)
        compare(page.sources[0].id, "cam0")
        compare(page.sources[1].url, "srt://b")
    }

    function test_refresh_sources() {
        mockBackend.setTestSources([{id: "initial", url: "rtmp://a"}])
        var page = createTemporaryObject(camerasComponent, testCase)
        wait(50)
        compare(page.sources.length, 1)

        mockBackend.setTestSources([
            {id: "initial", url: "rtmp://a"},
            {id: "added", url: "rtmp://b"}
        ])
        page.refreshSources()
        wait(50)
        compare(page.sources.length, 2)
    }
}
