import QtQuick
import QtTest
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "GlassComponents"
    when: windowShown
    width: 400
    height: 600

    // --- GlassCard Tests ---

    Component {
        id: glassCardComponent
        Components.GlassCard {
            width: 200
            height: 100

            Text {
                id: innerText
                text: "content"
                objectName: "innerText"
            }
        }
    }

    function test_glassCard_dimensions() {
        var card = createTemporaryObject(glassCardComponent, testCase)
        verify(card !== null, "GlassCard created")
        compare(card.width, 200)
        compare(card.height, 100)
    }

    function test_glassCard_default_properties() {
        var card = createTemporaryObject(glassCardComponent, testCase)
        compare(card.radius, WO.Theme.glassRadius)
        compare(card.hoverEnabled, false)
        compare(card.hovered, false)
        compare(card.surfaceOpacity, WO.Theme.glassOpacity)
    }

    function test_glassCard_content_accessible() {
        var card = createTemporaryObject(glassCardComponent, testCase)
        var inner = card.contentItem.children[0]
        verify(inner !== undefined, "Content child exists")
        compare(inner.objectName, "innerText")
        compare(inner.text, "content")
    }

    Component {
        id: hoverableCard
        Components.GlassCard {
            width: 200; height: 100
            hoverEnabled: true
        }
    }

    function test_glassCard_hover_enabled() {
        var card = createTemporaryObject(hoverableCard, testCase)
        compare(card.hoverEnabled, true)
        compare(card.hovered, false)
    }

    Component {
        id: customBorderCard
        Components.GlassCard {
            width: 200; height: 100
            borderColor: "red"
            radius: 8
            surfaceOpacity: 0.5
        }
    }

    function test_glassCard_custom_properties() {
        var card = createTemporaryObject(customBorderCard, testCase)
        compare(card.radius, 8)
        compare(card.surfaceOpacity, 0.5)
        compare(card.borderColor, Qt.color("red"))
    }

    // --- GlassButton Tests ---

    Component {
        id: glassButtonComponent
        Components.GlassButton {
            text: "Click Me"
        }
    }

    function test_glassButton_text() {
        var btn = createTemporaryObject(glassButtonComponent, testCase)
        verify(btn !== null, "GlassButton created")
        compare(btn.text, "Click Me")
    }

    function test_glassButton_default_state() {
        var btn = createTemporaryObject(glassButtonComponent, testCase)
        compare(btn.filled, false)
        compare(btn.iconText, "")
    }

    Component {
        id: filledButton
        Components.GlassButton {
            text: "Filled"
            filled: true
            accentColor: "#FF0000"
        }
    }

    function test_glassButton_filled() {
        var btn = createTemporaryObject(filledButton, testCase)
        compare(btn.filled, true)
        compare(btn.accentColor, Qt.color("#FF0000"))
    }

    SignalSpy { id: buttonSpy; signalName: "clicked" }

    function test_glassButton_click_signal() {
        var btn = createTemporaryObject(glassButtonComponent, testCase)
        buttonSpy.target = btn
        mouseClick(btn)
        compare(buttonSpy.count, 1)
    }

    Component {
        id: disabledButton
        Components.GlassButton {
            text: "Disabled"
            enabled: false
        }
    }

    function test_glassButton_disabled() {
        var btn = createTemporaryObject(disabledButton, testCase)
        compare(btn.enabled, false)
    }

    Component {
        id: iconButton
        Components.GlassButton {
            text: "Start"
            iconText: "\u25B6"
        }
    }

    function test_glassButton_icon() {
        var btn = createTemporaryObject(iconButton, testCase)
        compare(btn.iconText, "\u25B6")
        compare(btn.text, "Start")
    }

    // --- StatusBadge Tests ---

    Component {
        id: statusBadgeComponent
        Components.StatusBadge {
            label: "Active"
            statusColor: "#4CAF50"
            active: true
        }
    }

    function test_statusBadge_properties() {
        var badge = createTemporaryObject(statusBadgeComponent, testCase)
        verify(badge !== null, "StatusBadge created")
        compare(badge.label, "Active")
        compare(badge.active, true)
    }

    Component {
        id: inactiveBadge
        Components.StatusBadge {
            label: "Offline"
            statusColor: "#F44336"
            active: false
        }
    }

    function test_statusBadge_inactive() {
        var badge = createTemporaryObject(inactiveBadge, testCase)
        compare(badge.label, "Offline")
        compare(badge.active, false)
    }

    function test_statusBadge_dimensions() {
        var badge = createTemporaryObject(statusBadgeComponent, testCase)
        compare(badge.implicitHeight, WO.Theme.statusBadgeHeight)
        verify(badge.implicitWidth > 0)
    }

    // --- SearchField Tests ---

    Component {
        id: searchFieldComponent
        Components.SearchField {
            width: 300
            placeholder: "Type here..."
        }
    }

    function test_searchField_placeholder() {
        var field = createTemporaryObject(searchFieldComponent, testCase)
        verify(field !== null)
        compare(field.placeholder, "Type here...")
        compare(field.placeholderText, "Type here...")
    }

    function test_searchField_typing() {
        var field = createTemporaryObject(searchFieldComponent, testCase)
        mouseClick(field)
        keySequence("hello")
        compare(field.text, "hello")
    }

    function test_searchField_height() {
        var field = createTemporaryObject(searchFieldComponent, testCase)
        compare(field.implicitHeight, WO.Theme.inputHeight)
    }

    // --- GlassPanel Tests ---

    Component {
        id: glassPanelComponent
        Components.GlassPanel {
            width: 300; height: 200
        }
    }

    function test_glassPanel_creation() {
        var panel = createTemporaryObject(glassPanelComponent, testCase)
        verify(panel !== null, "GlassPanel created")
        compare(panel.width, 300)
        compare(panel.height, 200)
    }
}
