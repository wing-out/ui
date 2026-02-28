import QtQuick
import QtTest
import "../../qml/dialogs" as Dialogs
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "InitialSetup"
    when: windowShown
    width: 600
    height: 800

    Component {
        id: setupComponent
        Dialogs.InitialSetup {
            width: 600
            height: 800
        }
    }

    SignalSpy { id: setupCompleteSpy; signalName: "setupComplete" }

    function test_creation() {
        var setup = createTemporaryObject(setupComponent, testCase)
        verify(setup !== null, "InitialSetup created")
    }

    function test_default_mode() {
        var setup = createTemporaryObject(setupComponent, testCase)
        compare(setup.selectedMode, "remote")
    }

    function test_mode_selection() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setup.selectedMode = "embedded"
        compare(setup.selectedMode, "embedded")
        setup.selectedMode = "hybrid"
        compare(setup.selectedMode, "hybrid")
        setup.selectedMode = "remote"
        compare(setup.selectedMode, "remote")
    }

    function test_host_field_exists() {
        var setup = createTemporaryObject(setupComponent, testCase)
        var hostField = findChild(setup, "hostField")
        verify(hostField !== null, "hostField exists")
    }

    function test_connect_button_exists() {
        var setup = createTemporaryObject(setupComponent, testCase)
        var btn = findChild(setup, "connectButton")
        verify(btn !== null, "connectButton exists")
    }

    function test_connect_disabled_when_host_empty_remote_mode() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setup.selectedMode = "remote"
        var hostField = findChild(setup, "hostField")
        var btn = findChild(setup, "connectButton")
        hostField.text = ""
        compare(btn.enabled, false, "Button disabled when host empty in remote mode")
    }

    function test_connect_enabled_when_host_filled() {
        var setup = createTemporaryObject(setupComponent, testCase)
        var hostField = findChild(setup, "hostField")
        var btn = findChild(setup, "connectButton")
        hostField.text = "192.168.1.1:3595"
        compare(btn.enabled, true, "Button enabled when host filled")
    }

    function test_connect_enabled_in_embedded_mode_no_host() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setup.selectedMode = "embedded"
        var hostField = findChild(setup, "hostField")
        var btn = findChild(setup, "connectButton")
        hostField.text = ""
        compare(btn.enabled, true, "Button enabled in embedded mode without host")
    }

    function test_embedded_default_host() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setupCompleteSpy.target = setup
        setup.selectedMode = "embedded"
        var hostField = findChild(setup, "hostField")
        hostField.text = ""
        var btn = findChild(setup, "connectButton")
        mouseClick(btn)
        compare(setupCompleteSpy.count, 1)
        // Embedded mode with empty host defaults to 127.0.0.1:3595
        compare(setupCompleteSpy.signalArguments[0][0], "127.0.0.1:3595")
        compare(setupCompleteSpy.signalArguments[0][1], "embedded")
    }

    function test_setup_complete_signal() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setupCompleteSpy.target = setup
        var hostField = findChild(setup, "hostField")
        hostField.text = "10.0.0.1:3595"
        setup.selectedMode = "remote"
        var btn = findChild(setup, "connectButton")
        mouseClick(btn)
        compare(setupCompleteSpy.count, 1)
        compare(setupCompleteSpy.signalArguments[0][0], "10.0.0.1:3595")
        compare(setupCompleteSpy.signalArguments[0][1], "remote")
    }

    function test_host_trimmed() {
        var setup = createTemporaryObject(setupComponent, testCase)
        setupCompleteSpy.target = setup
        var hostField = findChild(setup, "hostField")
        hostField.text = "  10.0.0.1:3595  "
        var btn = findChild(setup, "connectButton")
        mouseClick(btn)
        compare(setupCompleteSpy.signalArguments[0][0], "10.0.0.1:3595")
    }
}
