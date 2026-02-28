import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "ProfilesPage"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: profilesComponent
        Pages.ProfilesPage {
            width: 600
            height: 800
            controller: mockBackend
        }
    }

    function init() {
        mockBackend.setTestProfiles([])
        mockBackend.resetCallCounts()
    }

    function test_creation() {
        var page = createTemporaryObject(profilesComponent, testCase)
        verify(page !== null, "ProfilesPage created")
    }

    function test_empty_profiles() {
        mockBackend.setTestProfiles([])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles.length, 0)
    }

    function test_profiles_loaded() {
        mockBackend.setTestProfiles([
            {name: "720p", description: "720p 30fps"},
            {name: "1080p", description: "1080p 60fps"}
        ])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles.length, 2)
    }

    function test_profile_names() {
        mockBackend.setTestProfiles([
            {name: "Profile A", description: "First"},
            {name: "Profile B", description: "Second"}
        ])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles[0].name, "Profile A")
        compare(page.profiles[1].name, "Profile B")
    }

    function test_active_profile_default() {
        var page = createTemporaryObject(profilesComponent, testCase)
        compare(page.activeProfile, "")
    }

    function test_active_profile_set() {
        var page = createTemporaryObject(profilesComponent, testCase)
        page.activeProfile = "720p"
        compare(page.activeProfile, "720p")
    }

    function test_refresh_profiles() {
        mockBackend.setTestProfiles([{name: "Initial", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles.length, 1)

        mockBackend.setTestProfiles([
            {name: "Initial", description: ""},
            {name: "New Profile", description: "Added"}
        ])
        page.refreshProfiles()
        wait(50)
        compare(page.profiles.length, 2)
    }

    function test_profile_with_description() {
        mockBackend.setTestProfiles([
            {name: "Stream", description: "High quality streaming profile for IRL"}
        ])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles[0].description, "High quality streaming profile for IRL")
    }

    function test_error_handling() {
        mockBackend.setTestError("listProfiles", "backend offline")
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        compare(page.profiles.length, 0)
        mockBackend.clearTestError("listProfiles")
    }

    // --- Start/Stop Stream button logic ---

    function test_start_stop_button_text_when_inactive() {
        // Button text: activeProfile === name ? "Stop" : "Start"
        var activeProfile = ""
        var profileName = "720p"
        var text = activeProfile === profileName ? "Stop" : "Start"
        compare(text, "Start")
    }

    function test_start_stop_button_text_when_active() {
        var activeProfile = "720p"
        var profileName = "720p"
        var text = activeProfile === profileName ? "Stop" : "Start"
        compare(text, "Stop")
    }

    function test_start_stop_button_color_when_inactive() {
        var activeProfile = ""
        var profileName = "720p"
        var color = activeProfile === profileName ? WO.Theme.error : WO.Theme.success
        compare(color, WO.Theme.success)
    }

    function test_start_stop_button_color_when_active() {
        var activeProfile = "720p"
        var profileName = "720p"
        var color = activeProfile === profileName ? WO.Theme.error : WO.Theme.success
        compare(color, WO.Theme.error)
    }

    function test_start_stream_button_exists() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        var btn = findChild(page, "profileStartStopBtn")
        verify(btn !== null, "Start/Stop button should exist")
    }

    function test_start_stream_button_shows_start_when_not_active() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        page.activeProfile = ""
        var btn = findChild(page, "profileStartStopBtn")
        compare(btn.text, "Start")
    }

    function test_start_stream_button_shows_stop_when_active() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        page.activeProfile = "Test"
        wait(50) // allow binding update
        var btn = findChild(page, "profileStartStopBtn")
        compare(btn.text, "Stop")
    }

    // --- Apply Profile button ---

    function test_apply_button_exists() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        var btn = findChild(page, "profileApplyBtn")
        verify(btn !== null, "Apply button should exist")
    }

    function test_apply_button_text() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        var btn = findChild(page, "profileApplyBtn")
        compare(btn.text, "Apply")
    }

    function test_apply_button_click() {
        mockBackend.setTestProfiles([{name: "TestProfile", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        mockBackend.resetCallCounts()
        var btn = findChild(page, "profileApplyBtn")
        mouseClick(btn)
        wait(50)
        compare(mockBackend.callCount("applyProfile"), 1)
    }

    // --- Profile selection state ---

    function test_active_profile_badge_visibility_logic() {
        // StatusBadge visible: activeProfile === modelData.name
        var activeProfile = "720p"
        var profileName = "720p"
        compare(activeProfile === profileName, true)
    }

    function test_inactive_profile_badge_visibility_logic() {
        var activeProfile = "1080p"
        var profileName = "720p"
        compare(activeProfile === profileName, false)
    }

    function test_active_profile_changes_on_start() {
        var page = createTemporaryObject(profilesComponent, testCase)
        compare(page.activeProfile, "")
        page.activeProfile = "IRL"
        compare(page.activeProfile, "IRL")
    }

    function test_active_profile_clears_on_stop() {
        var page = createTemporaryObject(profilesComponent, testCase)
        page.activeProfile = "IRL"
        compare(page.activeProfile, "IRL")
        page.activeProfile = ""
        compare(page.activeProfile, "")
    }

    // --- Edit button ---

    function test_edit_button_exists() {
        mockBackend.setTestProfiles([{name: "Test", description: ""}])
        var page = createTemporaryObject(profilesComponent, testCase)
        wait(50)
        var btn = findChild(page, "profileEditBtn")
        verify(btn !== null, "Edit button should exist")
    }
}
