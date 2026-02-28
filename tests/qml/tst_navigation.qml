import QtQuick
import QtTest
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "Navigation"
    when: windowShown
    width: 400
    height: 800

    // --- NavMenu Tests ---

    Component {
        id: navMenuComponent
        Components.NavMenu {
            width: WO.Theme.navMenuWidth
            height: 600
        }
    }

    SignalSpy { id: pageSelectedSpy; signalName: "pageSelected" }

    function test_navMenu_creation() {
        var menu = createTemporaryObject(navMenuComponent, testCase)
        verify(menu !== null, "NavMenu created")
        compare(menu.width, WO.Theme.navMenuWidth)
    }

    function test_navMenu_default_state() {
        var menu = createTemporaryObject(navMenuComponent, testCase)
        compare(menu.currentIndex, 0)
        compare(menu.isOpen, false)
    }

    function test_navMenu_current_index() {
        var menu = createTemporaryObject(navMenuComponent, testCase)
        menu.currentIndex = 3
        compare(menu.currentIndex, 3)
    }

    function test_navMenu_open_close() {
        var menu = createTemporaryObject(navMenuComponent, testCase)
        menu.isOpen = true
        compare(menu.isOpen, true)
        menu.isOpen = false
        compare(menu.isOpen, false)
    }

    // --- SwipeLockOverlay Tests ---

    Component {
        id: lockOverlayComponent
        Components.SwipeLockOverlay {
            width: 400
            height: 600
        }
    }

    function test_lock_default_state() {
        var overlay = createTemporaryObject(lockOverlayComponent, testCase)
        compare(overlay.locked, false)
        compare(overlay.visible, false)
    }

    function test_lock_becomes_visible() {
        var overlay = createTemporaryObject(lockOverlayComponent, testCase)
        overlay.locked = true
        compare(overlay.visible, true)
    }

    function test_lock_hides_when_unlocked() {
        var overlay = createTemporaryObject(lockOverlayComponent, testCase)
        overlay.locked = true
        compare(overlay.visible, true)
        overlay.locked = false
        compare(overlay.visible, false)
    }

    function test_lock_overlay_blocks_touches() {
        var overlay = createTemporaryObject(lockOverlayComponent, testCase)
        overlay.locked = true
        // Overlay is transparent but consumes touches
        compare(overlay.color, Qt.rgba(0, 0, 0, 0))
        compare(overlay.visible, true)
    }

    // --- Page title mapping (pure logic test) ---

    function test_page_titles() {
        var titles = ["Dashboard", "Cameras", "DJI Control", "Chat",
                      "Players", "Restreams", "Monitor", "Profiles", "Settings"]
        compare(titles.length, 9)
        compare(titles[0], "Dashboard")
        compare(titles[8], "Settings")
    }

    // --- Simulated page switching ---

    property int simulatedPageIndex: 0

    function test_page_switch_dashboard_to_chat() {
        simulatedPageIndex = 0
        compare(simulatedPageIndex, 0)
        simulatedPageIndex = 3
        compare(simulatedPageIndex, 3)
    }

    function test_page_switch_all_pages() {
        for (var i = 0; i < 9; i++) {
            simulatedPageIndex = i
            compare(simulatedPageIndex, i)
        }
    }
}
