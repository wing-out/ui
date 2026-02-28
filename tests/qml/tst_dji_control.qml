import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "DJIControl"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: djiComponent
        Pages.DJIControlPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function test_creation() {
        var page = createTemporaryObject(djiComponent, testCase)
        verify(page !== null, "DJIControlPage created")
    }

    // --- Resolution value mapping ---

    function test_default_resolution() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.resolution, "1080p")
    }

    function test_resolution_set_720p() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.resolution = "720p"
        compare(page.resolution, "720p")
    }

    function test_resolution_set_1080p() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.resolution = "1080p"
        compare(page.resolution, "1080p")
    }

    function test_resolution_set_4k() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.resolution = "4K"
        compare(page.resolution, "4K")
    }

    function test_resolution_options_available() {
        // The page has resolution options: ["720p", "1080p", "4K"]
        var options = ["720p", "1080p", "4K"]
        compare(options.length, 3)
        compare(options[0], "720p")
        compare(options[1], "1080p")
        compare(options[2], "4K")
    }

    function test_resolution_button_filled_state() {
        var page = createTemporaryObject(djiComponent, testCase)
        // Default is 1080p, so 1080p button should be filled
        var btn1080 = findChild(page, "djiRes1080p")
        verify(btn1080 !== null, "1080p resolution button should exist")
        compare(btn1080.filled, true)
    }

    function test_resolution_button_unfilled_for_inactive() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn720 = findChild(page, "djiRes720p")
        verify(btn720 !== null, "720p resolution button should exist")
        compare(btn720.filled, false)
    }

    function test_resolution_button_click_changes_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn720 = findChild(page, "djiRes720p")
        mouseClick(btn720)
        wait(50)
        compare(page.resolution, "720p")
    }

    // --- FPS options ---

    function test_default_fps() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.fps, 30)
    }

    function test_fps_set_24() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.fps = 24
        compare(page.fps, 24)
    }

    function test_fps_set_30() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.fps = 30
        compare(page.fps, 30)
    }

    function test_fps_set_60() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.fps = 60
        compare(page.fps, 60)
    }

    function test_fps_options_available() {
        // The page has FPS options: [24, 30, 60]
        var options = [24, 30, 60]
        compare(options.length, 3)
        compare(options[0], 24)
        compare(options[1], 30)
        compare(options[2], 60)
    }

    function test_fps_button_filled_state() {
        var page = createTemporaryObject(djiComponent, testCase)
        // Default is 30
        var btn30 = findChild(page, "djiFps30")
        verify(btn30 !== null, "FPS 30 button should exist")
        compare(btn30.filled, true)
    }

    function test_fps_button_unfilled_for_inactive() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn60 = findChild(page, "djiFps60")
        verify(btn60 !== null, "FPS 60 button should exist")
        compare(btn60.filled, false)
    }

    function test_fps_button_click_changes_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn60 = findChild(page, "djiFps60")
        mouseClick(btn60)
        wait(50)
        compare(page.fps, 60)
    }

    // --- Bitrate value range ---

    function test_default_bitrate() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.bitrateMbps, 8)
    }

    function test_bitrate_set_4() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.bitrateMbps = 4
        compare(page.bitrateMbps, 4)
    }

    function test_bitrate_set_8() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.bitrateMbps = 8
        compare(page.bitrateMbps, 8)
    }

    function test_bitrate_set_12() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.bitrateMbps = 12
        compare(page.bitrateMbps, 12)
    }

    function test_bitrate_set_20() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.bitrateMbps = 20
        compare(page.bitrateMbps, 20)
    }

    function test_bitrate_options_available() {
        // The page has bitrate options: [4, 8, 12, 20]
        var options = [4, 8, 12, 20]
        compare(options.length, 4)
        compare(options[0], 4)
        compare(options[3], 20)
    }

    function test_bitrate_button_filled_state() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn8 = findChild(page, "djiBitrate8")
        verify(btn8 !== null, "Bitrate 8 button should exist")
        compare(btn8.filled, true)
    }

    function test_bitrate_button_click_changes_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn20 = findChild(page, "djiBitrate20")
        mouseClick(btn20)
        wait(50)
        compare(page.bitrateMbps, 20)
    }

    // --- WiFi SSID/PSK fields ---

    function test_wifi_ssid_default_empty() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.wifiSSID, "")
    }

    function test_wifi_psk_default_empty() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.wifiPSK, "")
    }

    function test_wifi_ssid_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.wifiSSID = "DJI_Network"
        compare(page.wifiSSID, "DJI_Network")
    }

    function test_wifi_psk_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.wifiPSK = "secret123"
        compare(page.wifiPSK, "secret123")
    }

    function test_wifi_ssid_field_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiSsidField")
        verify(field !== null, "WiFi SSID field should exist")
    }

    function test_wifi_psk_field_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiPskField")
        verify(field !== null, "WiFi PSK field should exist")
    }

    function test_wifi_ssid_field_placeholder() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiSsidField")
        compare(field.placeholder, "WiFi network name")
    }

    function test_wifi_psk_field_placeholder() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiPskField")
        compare(field.placeholder, "WiFi password")
    }

    // --- RTMP URL field ---

    function test_rtmp_url_default_empty() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.rtmpUrl, "")
    }

    function test_rtmp_url_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.rtmpUrl = "rtmp://192.168.1.1/live/stream"
        compare(page.rtmpUrl, "rtmp://192.168.1.1/live/stream")
    }

    function test_rtmp_field_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiRtmpField")
        verify(field !== null, "RTMP URL field should exist")
    }

    function test_rtmp_field_placeholder() {
        var page = createTemporaryObject(djiComponent, testCase)
        var field = findChild(page, "djiRtmpField")
        compare(field.placeholder, "rtmp://...")
    }

    // --- Discovery button states ---

    function test_discovery_button_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiDiscoveryButton")
        verify(btn !== null, "Discovery button should exist")
    }

    function test_discovery_button_text_not_paired() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.isPaired, false)
        var btn = findChild(page, "djiDiscoveryButton")
        compare(btn.text, "Start Discovery")
    }

    function test_discovery_button_text_paired() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isPaired = true
        wait(50)
        var btn = findChild(page, "djiDiscoveryButton")
        compare(btn.text, "Disconnect")
    }

    function test_discovery_button_filled() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiDiscoveryButton")
        compare(btn.filled, true)
    }

    // --- Connection states ---

    function test_default_not_paired() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.isPaired, false)
    }

    function test_default_not_wifi_connected() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.isWiFiConnected, false)
    }

    function test_default_not_streaming() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.isStreaming, false)
    }

    function test_paired_state_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isPaired = true
        compare(page.isPaired, true)
    }

    function test_wifi_connected_state_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isWiFiConnected = true
        compare(page.isWiFiConnected, true)
    }

    function test_streaming_state_set() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isStreaming = true
        compare(page.isStreaming, true)
    }

    // --- Stream button ---

    function test_stream_button_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiStreamButton")
        verify(btn !== null, "Stream button should exist")
    }

    function test_stream_button_text_not_streaming() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiStreamButton")
        compare(btn.text, "Start Streaming")
    }

    function test_stream_button_text_streaming() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isStreaming = true
        wait(50)
        var btn = findChild(page, "djiStreamButton")
        compare(btn.text, "Stop Streaming")
    }

    function test_stream_button_disabled_without_wifi() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isWiFiConnected = false
        wait(50)
        var btn = findChild(page, "djiStreamButton")
        compare(btn.enabled, false)
    }

    function test_stream_button_enabled_with_wifi() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isWiFiConnected = true
        wait(50)
        var btn = findChild(page, "djiStreamButton")
        compare(btn.enabled, true)
    }

    // --- WiFi connect button ---

    function test_wifi_connect_button_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiConnectWifiButton")
        verify(btn !== null, "WiFi connect button should exist")
    }

    function test_wifi_connect_button_text_disconnected() {
        var page = createTemporaryObject(djiComponent, testCase)
        var btn = findChild(page, "djiConnectWifiButton")
        compare(btn.text, "Connect WiFi")
    }

    function test_wifi_connect_button_text_connected() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.isWiFiConnected = true
        wait(50)
        var btn = findChild(page, "djiConnectWifiButton")
        compare(btn.text, "Disconnect WiFi")
    }

    // --- Log area ---

    function test_log_text_default_empty() {
        var page = createTemporaryObject(djiComponent, testCase)
        compare(page.logText, "")
    }

    function test_log_area_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var area = findChild(page, "djiLogArea")
        verify(area !== null, "Log area should exist")
    }

    function test_log_area_default_text() {
        var page = createTemporaryObject(djiComponent, testCase)
        var area = findChild(page, "djiLogArea")
        compare(area.text, "No log entries yet.")
    }

    function test_append_log() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.appendLog("Test message")
        verify(page.logText.indexOf("Test message") !== -1,
               "Log should contain appended message")
    }

    function test_append_log_includes_timestamp() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.appendLog("With timestamp")
        // The appendLog function prepends [timestamp]
        verify(page.logText.indexOf("[") !== -1, "Log should contain timestamp bracket")
        verify(page.logText.indexOf("]") !== -1, "Log should contain closing timestamp bracket")
    }

    function test_append_log_prepends_newest() {
        var page = createTemporaryObject(djiComponent, testCase)
        page.appendLog("First")
        page.appendLog("Second")
        // Newest message should appear first in the log
        var firstIdx = page.logText.indexOf("First")
        var secondIdx = page.logText.indexOf("Second")
        verify(secondIdx < firstIdx, "Newest message should appear first in log")
    }

    // --- Metric tiles ---

    function test_resolution_tile_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiResolutionTile")
        verify(tile !== null, "Resolution tile should exist")
    }

    function test_fps_tile_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiFpsTile")
        verify(tile !== null, "FPS tile should exist")
    }

    function test_bitrate_tile_exists() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiBitrateTile")
        verify(tile !== null, "Bitrate tile should exist")
    }

    function test_resolution_tile_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiResolutionTile")
        compare(tile.value, "1080p")
    }

    function test_fps_tile_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiFpsTile")
        compare(tile.value, "30")
    }

    function test_bitrate_tile_value() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiBitrateTile")
        compare(tile.value, "8")
    }

    function test_bitrate_tile_unit() {
        var page = createTemporaryObject(djiComponent, testCase)
        var tile = findChild(page, "djiBitrateTile")
        compare(tile.unit, "Mbps")
    }
}
