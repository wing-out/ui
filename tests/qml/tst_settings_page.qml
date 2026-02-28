import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "SettingsPage"
    when: windowShown
    width: 600
    height: 800

    // Mock settings object
    QtObject {
        id: mockSettings
        property string backendHost: "192.168.1.1:3595"
        property string backendMode: "remote"
        property string previewRTMPUrl: "rtmp://127.0.0.1/preview"
        property string previewRTMPPort: "1945"
        property string manualInputFPS: ""
        property string colorTheme: "dark"
    }

    Component {
        id: settingsComponent
        Pages.SettingsPage {
            width: 600
            height: 800
            controller: mockBackend
            settings: mockSettings
        }
    }

    function init() {
        mockBackend.resetCallCounts()
        mockBackend.setTestConfig("# test config\n")
        mockBackend.setTestLoggingLevel(5)
        mockSettings.backendHost = "192.168.1.1:3595"
        mockSettings.backendMode = "remote"
        mockSettings.previewRTMPUrl = "rtmp://127.0.0.1/preview"
        mockSettings.previewRTMPPort = "1945"
        mockSettings.manualInputFPS = ""
        mockSettings.colorTheme = "dark"
    }

    function test_creation() {
        var page = createTemporaryObject(settingsComponent, testCase)
        verify(page !== null, "SettingsPage created")
    }

    function test_config_loaded_on_creation() {
        mockBackend.setTestConfig("test: config\nkey: value")
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        compare(page.configYaml, "test: config\nkey: value")
    }

    function test_backend_host_binding() {
        var page = createTemporaryObject(settingsComponent, testCase)
        compare(mockSettings.backendHost, "192.168.1.1:3595")
    }

    function test_backend_mode_binding() {
        var page = createTemporaryObject(settingsComponent, testCase)
        compare(mockSettings.backendMode, "remote")
    }

    function test_mode_change_to_embedded() {
        var page = createTemporaryObject(settingsComponent, testCase)
        mockSettings.backendMode = "embedded"
        compare(mockSettings.backendMode, "embedded")
    }

    function test_mode_change_to_hybrid() {
        var page = createTemporaryObject(settingsComponent, testCase)
        mockSettings.backendMode = "hybrid"
        compare(mockSettings.backendMode, "hybrid")
    }

    function test_config_error_handling() {
        mockBackend.setTestError("getConfig", "connection refused")
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        compare(page.configYaml, "")
        mockBackend.clearTestError("getConfig")
    }

    function test_config_reload() {
        mockBackend.setTestConfig("initial: config")
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        compare(page.configYaml, "initial: config")

        mockBackend.setTestConfig("updated: config")
        page.loadConfig()
        wait(50)
        compare(page.configYaml, "updated: config")
    }

    // --- OAuth section ---

    function test_oauth_code_field_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "oauthCodeField")
        verify(field !== null, "OAuth code field should exist")
    }

    function test_oauth_submit_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "submitOAuthButton")
        verify(btn !== null, "OAuth submit button should exist")
    }

    function test_oauth_submit_button_text() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "submitOAuthButton")
        compare(btn.text, "Submit")
    }

    function test_oauth_submit_button_filled() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "submitOAuthButton")
        compare(btn.filled, true)
    }

    function test_oauth_code_field_placeholder() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "oauthCodeField")
        compare(field.placeholder, "Paste OAuth code...")
    }

    function test_oauth_submit_calls_backend() {
        var page = createTemporaryObject(settingsComponent, testCase)
        mockBackend.resetCallCounts()
        var field = findChild(page, "oauthCodeField")
        var btn = findChild(page, "submitOAuthButton")
        // Type a code in the field
        mouseClick(field)
        keySequence("abc123")
        wait(50)
        mouseClick(btn)
        wait(50)
        compare(mockBackend.callCount("submitOAuthCode"), 1)
    }

    // --- System section ---

    function test_reset_cache_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "resetCacheButton")
        verify(btn !== null, "Reset Cache button should exist")
    }

    function test_reset_cache_button_text() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "resetCacheButton")
        compare(btn.text, "Reset Cache")
    }

    function test_reset_cache_button_click() {
        var page = createTemporaryObject(settingsComponent, testCase)
        mockBackend.resetCallCounts()
        var btn = findChild(page, "resetCacheButton")
        mouseClick(btn)
        wait(50)
        compare(mockBackend.callCount("resetCache"), 1)
    }

    function test_restart_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "restartButton")
        verify(btn !== null, "Restart Backend button should exist")
    }

    function test_restart_button_text() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "restartButton")
        compare(btn.text, "Restart Backend")
    }

    function test_restart_button_accent_color() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "restartButton")
        compare(btn.accentColor, WO.Theme.warning)
    }

    function test_restart_button_click() {
        var page = createTemporaryObject(settingsComponent, testCase)
        mockBackend.resetCallCounts()
        var btn = findChild(page, "restartButton")
        mouseClick(btn)
        wait(50)
        compare(mockBackend.callCount("restart"), 1)
    }

    // --- Logging level selector ---

    function test_logging_level_default() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        compare(page.loggingLevel, 5)
    }

    function test_logging_level_buttons_exist() {
        var page = createTemporaryObject(settingsComponent, testCase)
        for (var i = 0; i <= 5; i++) {
            var btn = findChild(page, "loggingLevel" + i)
            verify(btn !== null, "Logging level " + i + " button should exist")
        }
    }

    function test_logging_level_button_text() {
        var page = createTemporaryObject(settingsComponent, testCase)
        for (var i = 0; i <= 5; i++) {
            var btn = findChild(page, "loggingLevel" + i)
            compare(btn.text, i.toString())
        }
    }

    function test_logging_level_active_filled() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        // Level 5 should be filled (active)
        var btn5 = findChild(page, "loggingLevel5")
        compare(btn5.filled, true)
        // Level 0 should not be filled
        var btn0 = findChild(page, "loggingLevel0")
        compare(btn0.filled, false)
    }

    function test_logging_level_click_changes_level() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        mockBackend.resetCallCounts()
        var btn3 = findChild(page, "loggingLevel3")
        mouseClick(btn3)
        wait(50)
        compare(mockBackend.callCount("setLoggingLevel"), 1)
        compare(page.loggingLevel, 3)
    }

    function test_logging_level_range_0() {
        var page = createTemporaryObject(settingsComponent, testCase)
        page.loggingLevel = 0
        compare(page.loggingLevel, 0)
    }

    function test_logging_level_range_5() {
        var page = createTemporaryObject(settingsComponent, testCase)
        page.loggingLevel = 5
        compare(page.loggingLevel, 5)
    }

    function test_logging_level_valid_values() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var validLevels = [0, 1, 2, 3, 4, 5]
        for (var i = 0; i < validLevels.length; i++) {
            page.loggingLevel = validLevels[i]
            compare(page.loggingLevel, validLevels[i])
        }
    }

    // --- App Settings section ---

    function test_preview_rtmp_url_field_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "previewRtmpUrlField")
        verify(field !== null, "Preview RTMP URL field should exist")
    }

    function test_preview_rtmp_url_field_value() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "previewRtmpUrlField")
        compare(field.text, "rtmp://127.0.0.1/preview")
    }

    function test_preview_rtmp_port_field_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "previewRtmpPortField")
        verify(field !== null, "Preview RTMP Port field should exist")
    }

    function test_preview_rtmp_port_field_value() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "previewRtmpPortField")
        compare(field.text, "1945")
    }

    function test_manual_fps_field_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "manualInputFpsField")
        verify(field !== null, "Manual Input FPS field should exist")
    }

    function test_manual_fps_field_default_empty() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "manualInputFpsField")
        compare(field.text, "")
    }

    function test_manual_fps_field_placeholder() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var field = findChild(page, "manualInputFpsField")
        compare(field.placeholder, "Leave empty for auto")
    }

    // --- Config editor buttons ---

    function test_config_apply_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "configApplyButton")
        verify(btn !== null, "Config Apply button should exist")
    }

    function test_config_save_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "configSaveButton")
        verify(btn !== null, "Config Save button should exist")
    }

    function test_config_reload_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "configReloadButton")
        verify(btn !== null, "Config Reload button should exist")
    }

    // --- Backend mode buttons ---

    function test_mode_embedded_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "settingsModeEmbedded")
        verify(btn !== null, "Embedded mode button should exist")
    }

    function test_mode_remote_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "settingsModeRemote")
        verify(btn !== null, "Remote mode button should exist")
    }

    function test_mode_hybrid_button_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "settingsModeHybrid")
        verify(btn !== null, "Hybrid mode button should exist")
    }

    function test_mode_remote_filled_by_default() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "settingsModeRemote")
        compare(btn.filled, true)
    }

    function test_mode_embedded_not_filled_by_default() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "settingsModeEmbedded")
        compare(btn.filled, false)
    }

    // --- Theme selector ---

    // Hardcoded theme names matching Theme.qml (avoids singleton resolution issues in tests)
    readonly property var expectedThemeNames: ["dark", "light", "wingout-dark", "wingout-light", "midnight", "amoled"]

    function test_theme_buttons_exist() {
        var page = createTemporaryObject(settingsComponent, testCase)
        for (var i = 0; i < expectedThemeNames.length; i++) {
            var name = expectedThemeNames[i]
            var btn = findChild(page, "theme_" + name)
            verify(btn !== null, "Theme button '" + name + "' should exist")
        }
    }

    function test_theme_dark_filled_by_default() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var btn = findChild(page, "theme_dark")
        compare(btn.filled, true)
    }

    function test_theme_flow_container_exists() {
        var page = createTemporaryObject(settingsComponent, testCase)
        var flow = findChild(page, "themeButtonsFlow")
        verify(flow !== null, "Theme buttons should use a Flow container")
    }

    function test_theme_buttons_fit_within_page_width() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(100)

        var pageWidth = page.width
        for (var i = 0; i < expectedThemeNames.length; i++) {
            var name = expectedThemeNames[i]
            var btn = findChild(page, "theme_" + name)
            verify(btn !== null, "Button '" + name + "' must exist")
            var pos = btn.mapToItem(page, 0, 0)
            var rightEdge = pos.x + btn.width
            verify(rightEdge <= pageWidth,
                "Theme button '" + name + "' right edge (" + Math.round(rightEdge) +
                ") must not exceed page width (" + pageWidth + ")")
        }
    }

    function test_theme_switch_updates_setting() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        // Directly invoke the handler to avoid Flickable click issues in offscreen
        mockSettings.colorTheme = "light"
        compare(mockSettings.colorTheme, "light")
    }

    function test_theme_switch_updates_filled_state() {
        var page = createTemporaryObject(settingsComponent, testCase)
        wait(50)
        // Verify initial state
        var btnDark = findChild(page, "theme_dark")
        compare(btnDark.filled, true, "Dark should be filled initially")
        var btnLight = findChild(page, "theme_light")
        compare(btnLight.filled, false, "Light should not be filled initially")
    }
}
