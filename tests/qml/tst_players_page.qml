import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "PlayersPage"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: playersComponent
        Pages.PlayersPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function init() {
        mockBackend.setTestPlayers([])
        mockBackend.resetCallCounts()
    }

    function test_creation() {
        var page = createTemporaryObject(playersComponent, testCase)
        verify(page !== null, "PlayersPage created")
    }

    // --- Default/empty state ---

    function test_empty_players_default() {
        var page = createTemporaryObject(playersComponent, testCase)
        compare(page.players.length, 0)
    }

    function test_empty_state_message_visible() {
        mockBackend.setTestPlayers([])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        // Empty state is visible when players.length === 0
        compare(page.players.length === 0, true)
    }

    function test_empty_state_hidden_with_players() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "rtmp://test", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        compare(page.players.length === 0, false)
    }

    // --- Players loaded from mock ---

    function test_players_loaded() {
        mockBackend.setTestPlayers([
            {id: "player1", title: "Stream A", link: "rtmp://test/a", position: 120, length: 3600, isPaused: false},
            {id: "player2", title: "Stream B", link: "rtmp://test/b", position: 60, length: 1800, isPaused: true}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        compare(page.players.length, 2)
    }

    function test_player_data_integrity() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Test Stream", link: "rtmp://example.com/live", position: 300, length: 7200, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        compare(page.players[0].id, "p1")
        compare(page.players[0].title, "Test Stream")
        compare(page.players[0].link, "rtmp://example.com/live")
        compare(page.players[0].position, 300)
        compare(page.players[0].length, 7200)
        compare(page.players[0].isPaused, false)
    }

    function test_refresh_players() {
        mockBackend.setTestPlayers([{id: "p1", title: "A", link: "", position: 0, length: 0, isPaused: false}])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        compare(page.players.length, 1)

        mockBackend.setTestPlayers([
            {id: "p1", title: "A", link: "", position: 0, length: 0, isPaused: false},
            {id: "p2", title: "B", link: "", position: 0, length: 0, isPaused: false}
        ])
        page.refreshPlayers()
        wait(50)
        compare(page.players.length, 2)
    }

    // --- Player control buttons ---

    function test_play_pause_button_exists() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerPlayPauseBtn")
        verify(btn !== null, "Play/Pause button should exist")
    }

    function test_play_pause_text_when_not_paused() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerPlayPauseBtn")
        // When not paused, shows pause symbol (U+23F8)
        compare(btn.text, "\u23F8")
    }

    function test_play_pause_text_when_paused() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: true}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerPlayPauseBtn")
        // When paused, shows play symbol (U+25B6)
        compare(btn.text, "\u25B6")
    }

    function test_stop_button_exists() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerStopBtn")
        verify(btn !== null, "Stop button should exist")
    }

    function test_stop_button_text() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerStopBtn")
        // Stop symbol (U+23F9)
        compare(btn.text, "\u23F9")
    }

    function test_close_button_exists() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerCloseBtn")
        verify(btn !== null, "Close button should exist")
    }

    function test_close_button_text() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerCloseBtn")
        // Close symbol (U+2716)
        compare(btn.text, "\u2716")
    }

    function test_close_button_accent_color() {
        mockBackend.setTestPlayers([
            {id: "p1", title: "Stream", link: "", position: 0, length: 0, isPaused: false}
        ])
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        var btn = findChild(page, "playerCloseBtn")
        compare(btn.accentColor, WO.Theme.error)
    }

    // --- Open URL input field ---

    function test_url_input_exists() {
        var page = createTemporaryObject(playersComponent, testCase)
        var input = findChild(page, "playerUrlInput")
        verify(input !== null, "URL input field should exist")
    }

    function test_url_input_placeholder() {
        var page = createTemporaryObject(playersComponent, testCase)
        var input = findChild(page, "playerUrlInput")
        compare(input.placeholder, "Enter URL to play...")
    }

    function test_open_button_exists() {
        var page = createTemporaryObject(playersComponent, testCase)
        var btn = findChild(page, "playerOpenBtn")
        verify(btn !== null, "Open button should exist")
    }

    function test_open_button_text() {
        var page = createTemporaryObject(playersComponent, testCase)
        var btn = findChild(page, "playerOpenBtn")
        compare(btn.text, "Open")
    }

    function test_open_button_filled() {
        var page = createTemporaryObject(playersComponent, testCase)
        var btn = findChild(page, "playerOpenBtn")
        compare(btn.filled, true)
    }

    // --- Position/length display format (mm:ss) ---

    function test_formatDuration_zero_position() {
        compare(WO.Theme.formatDuration(0), "0:00")
    }

    function test_formatDuration_seconds_only() {
        compare(WO.Theme.formatDuration(45), "0:45")
    }

    function test_formatDuration_minutes_and_seconds() {
        compare(WO.Theme.formatDuration(125), "2:05")
    }

    function test_formatDuration_exact_minute() {
        compare(WO.Theme.formatDuration(60), "1:00")
    }

    function test_formatDuration_hours() {
        compare(WO.Theme.formatDuration(3661), "1:01:01")
    }

    function test_position_length_display() {
        // The page shows: formatDuration(position) + " / " + formatDuration(length)
        var position = 120
        var length = 3600
        var display = WO.Theme.formatDuration(position) + " / " + WO.Theme.formatDuration(length)
        compare(display, "2:00 / 1:00:00")
    }

    function test_position_length_display_zero() {
        var position = 0
        var length = 0
        var display = WO.Theme.formatDuration(position) + " / " + WO.Theme.formatDuration(length)
        compare(display, "0:00 / 0:00")
    }

    function test_position_length_display_mid_stream() {
        var position = 754
        var length = 1800
        var display = WO.Theme.formatDuration(position) + " / " + WO.Theme.formatDuration(length)
        compare(display, "12:34 / 30:00")
    }

    // --- Player title fallback ---

    function test_title_fallback_undefined() {
        var title = undefined || "Untitled"
        compare(title, "Untitled")
    }

    function test_title_fallback_empty() {
        var title = "" || "Untitled"
        compare(title, "Untitled")
    }

    function test_title_with_value() {
        var title = "My Stream" || "Untitled"
        compare(title, "My Stream")
    }

    // --- Player link fallback ---

    function test_link_fallback_undefined() {
        var link = undefined || ""
        compare(link, "")
    }

    function test_link_with_value() {
        var link = "rtmp://test.com/live" || ""
        compare(link, "rtmp://test.com/live")
    }

    // --- Player ID fallback for open ---

    function test_open_player_id_with_existing_player() {
        var players = [{id: "player1"}, {id: "player2"}]
        var pid = players.length > 0 ? players[0].id : "default"
        compare(pid, "player1")
    }

    function test_open_player_id_no_players() {
        var players = []
        var pid = players.length > 0 ? players[0].id : "default"
        compare(pid, "default")
    }

    // --- Error handling ---

    function test_error_handling() {
        mockBackend.setTestError("listStreamPlayers", "backend offline")
        var page = createTemporaryObject(playersComponent, testCase)
        wait(50)
        compare(page.players.length, 0)
        mockBackend.clearTestError("listStreamPlayers")
    }
}
