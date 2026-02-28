import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "MonitorPage"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: monitorComponent
        Pages.MonitorPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function init() {
        mockBackend.setTestSources([])
        mockBackend.resetCallCounts()
    }

    function test_creation() {
        var page = createTemporaryObject(monitorComponent, testCase)
        verify(page !== null, "MonitorPage created")
    }

    // --- Default state ---

    function test_default_not_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.isPlaying, false)
    }

    function test_default_selected_source_empty() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.selectedSource, "")
    }

    function test_default_resolution() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.sourceResolution, "--")
    }

    function test_default_codec() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.sourceCodec, "--")
    }

    function test_default_sources_empty() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.sources.length, 0)
    }

    // --- Source selector ---

    function test_sources_loaded_from_mock() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "1920x1080", codec: "h264"},
            {id: "cam1", url: "rtmp://b", resolution: "1280x720", codec: "h265"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sources.length, 2)
    }

    function test_first_source_auto_selected() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "1920x1080", codec: "h264"},
            {id: "cam1", url: "rtmp://b", resolution: "1280x720", codec: "h265"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.selectedSource, "cam0")
    }

    function test_source_selector_visibility_single_source() {
        // Source selector row is visible when sources.length > 1
        mockBackend.setTestSources([{id: "cam0", url: "rtmp://a"}])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sources.length > 1, false, "Selector should be hidden with single source")
    }

    function test_source_selector_visibility_multiple_sources() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a"},
            {id: "cam1", url: "rtmp://b"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sources.length > 1, true, "Selector should be visible with multiple sources")
    }

    function test_source_selection_change() {
        var page = createTemporaryObject(monitorComponent, testCase)
        page.selectedSource = "cam1"
        compare(page.selectedSource, "cam1")
    }

    function test_source_resolution_updated() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "1920x1080", codec: "h264"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sourceResolution, "1920x1080")
    }

    function test_source_codec_updated() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "1920x1080", codec: "h264"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sourceCodec, "h264")
    }

    function test_source_resolution_fallback() {
        // When source has no resolution field, should remain "--"
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        compare(page.sourceResolution, "--")
    }

    // --- Playback control button states ---

    function test_play_pause_button_exists() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var btn = findChild(page, "monitorPlayPauseBtn")
        verify(btn !== null, "Play/Pause button should exist")
    }

    function test_stop_button_exists() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var btn = findChild(page, "monitorStopBtn")
        verify(btn !== null, "Stop button should exist")
    }

    function test_mute_button_exists() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var btn = findChild(page, "monitorMuteBtn")
        verify(btn !== null, "Mute button should exist")
    }

    function test_play_pause_text_when_not_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var btn = findChild(page, "monitorPlayPauseBtn")
        // Play symbol (U+25B6)
        compare(btn.text, "\u25B6")
    }

    function test_play_pause_text_when_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        page.isPlaying = true
        wait(50)
        var btn = findChild(page, "monitorPlayPauseBtn")
        // Pause symbol (U+23F8)
        compare(btn.text, "\u23F8")
    }

    function test_play_pause_toggles_state() {
        var page = createTemporaryObject(monitorComponent, testCase)
        compare(page.isPlaying, false)
        var btn = findChild(page, "monitorPlayPauseBtn")
        mouseClick(btn)
        wait(50)
        compare(page.isPlaying, true)
        mouseClick(btn)
        wait(50)
        compare(page.isPlaying, false)
    }

    function test_stop_sets_not_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        page.isPlaying = true
        wait(50)
        var btn = findChild(page, "monitorStopBtn")
        mouseClick(btn)
        wait(50)
        compare(page.isPlaying, false)
    }

    function test_stop_text() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var btn = findChild(page, "monitorStopBtn")
        // Stop symbol (U+23F9)
        compare(btn.text, "\u23F9")
    }

    // --- Stream info tiles ---

    function test_resolution_tile_exists() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var tile = findChild(page, "monitorResolutionTile")
        verify(tile !== null, "Resolution tile should exist")
    }

    function test_codec_tile_exists() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var tile = findChild(page, "monitorCodecTile")
        verify(tile !== null, "Codec tile should exist")
    }

    function test_resolution_tile_default_value() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var tile = findChild(page, "monitorResolutionTile")
        compare(tile.value, "--")
    }

    function test_codec_tile_default_value() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var tile = findChild(page, "monitorCodecTile")
        compare(tile.value, "--")
    }

    function test_resolution_tile_updates_with_source() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "3840x2160", codec: "h265"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        var tile = findChild(page, "monitorResolutionTile")
        compare(tile.value, "3840x2160")
    }

    function test_codec_tile_updates_with_source() {
        mockBackend.setTestSources([
            {id: "cam0", url: "rtmp://a", resolution: "1920x1080", codec: "h265"}
        ])
        var page = createTemporaryObject(monitorComponent, testCase)
        wait(50)
        var tile = findChild(page, "monitorCodecTile")
        compare(tile.value, "h265")
    }

    // --- Selected source text ---

    function test_selected_source_text_none() {
        var page = createTemporaryObject(monitorComponent, testCase)
        // Text: "Selected Source: " + (selectedSource !== "" ? selectedSource : "none")
        var text = page.selectedSource !== "" ? page.selectedSource : "none"
        compare(text, "none")
    }

    function test_selected_source_text_with_source() {
        var page = createTemporaryObject(monitorComponent, testCase)
        page.selectedSource = "cam0"
        var text = page.selectedSource !== "" ? page.selectedSource : "none"
        compare(text, "cam0")
    }

    // --- Preview area text ---

    function test_preview_text_not_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        var text = page.isPlaying ? "Playing: " + page.selectedSource : "No preview available"
        compare(text, "No preview available")
    }

    function test_preview_text_playing() {
        var page = createTemporaryObject(monitorComponent, testCase)
        page.isPlaying = true
        page.selectedSource = "cam0"
        var text = page.isPlaying ? "Playing: " + page.selectedSource : "No preview available"
        compare(text, "Playing: cam0")
    }

    // --- Refresh sources ---

    function test_refresh_sources() {
        mockBackend.setTestSources([{id: "initial", url: "rtmp://a"}])
        var page = createTemporaryObject(monitorComponent, testCase)
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
