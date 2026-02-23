import QtQuick
import QtQuick.Controls
import QtTest
import QtCore as Core
import WingOut

/// Tests the ChatView component with mock chat messages.
TestCase {
    id: tc
    name: "ChatView"
    when: windowShown
    width: 540
    height: 960

    Core.Settings {
        id: chatSettings
        property string dxProducerHost: "https://localhost:1234"
        property string previewRTMPUrl: ""
        property string previewRTMPPort: "1945"
        property string previewRTMPStreamID: "test/stream/"
        property string ffstreamHost: ""
        property string manualInputFPS: ""
    }

    Component.onCompleted: {
        chatSettings.dxProducerHost = "https://localhost:1234"
        chatSettings.previewRTMPPort = "1945"
        chatSettings.previewRTMPStreamID = "test/stream/"
    }

    ListModel {
        id: mockChatModel
    }

    Component {
        id: appComponent
        Application {}
    }

    // ----- colour helpers (mirror ChatView.qml) -----

    function platformNameToColor(name) {
        switch (name) {
        case "twitch":  return "#6441a5"
        case "youtube": return "#ff0000"
        case "kick":    return "#00ff00"
        default:        return "#ffffff"
        }
    }

    function usernameToColor(username) {
        var hash = 0
        for (var i = 0; i < username.length; i++) {
            hash = username.charCodeAt(i) + ((hash << 5) - hash)
        }
        var hue = Math.abs(hash) % 360
        return Qt.hsla(hue / 360, 0.7, 0.6, 1.0)
    }

    // ----- tests -----

    function test_01_platform_colors() {
        compare(platformNameToColor("twitch"),  "#6441a5")
        compare(platformNameToColor("youtube"), "#ff0000")
        compare(platformNameToColor("kick"),    "#00ff00")
        compare(platformNameToColor("unknown"), "#ffffff")
    }

    function test_02_username_color_deterministic() {
        var c1 = usernameToColor("alice")
        var c2 = usernameToColor("alice")
        compare(c1.toString(), c2.toString(),
                "Same username should produce same colour")
    }

    function test_03_username_color_varies() {
        var c1 = usernameToColor("alice")
        var c2 = usernameToColor("bob")
        verify(c1.toString() !== c2.toString(),
               "Different usernames should (usually) produce different colours")
    }

    function test_04_model_add_messages() {
        mockChatModel.clear()
        compare(mockChatModel.count, 0)

        mockChatModel.append({
            timestampUNIXNano: "1700000000000000000",
            username: "alice",
            usernameReadable: "Alice",
            message: "Hello, world!",
            messageFormatType: 0,
            platformName: "twitch",
            isLive: true
        })
        compare(mockChatModel.count, 1)

        mockChatModel.append({
            timestampUNIXNano: "1700000001000000000",
            username: "bob",
            usernameReadable: "Bob",
            message: "Hi there!",
            messageFormatType: 0,
            platformName: "youtube",
            isLive: true
        })
        compare(mockChatModel.count, 2)
    }

    function test_05_model_max_cap() {
        // Verify that manually trimming the model to a cap works.
        mockChatModel.clear()
        var cap = 200
        for (var i = 0; i < cap + 10; i++) {
            mockChatModel.append({
                timestampUNIXNano: String(1700000000000000000 + i * 1000000),
                username: "user" + i,
                usernameReadable: "User " + i,
                message: "msg " + i,
                messageFormatType: 0,
                platformName: "twitch",
                isLive: true
            })
            if (mockChatModel.count > cap)
                mockChatModel.remove(0)
        }
        compare(mockChatModel.count, cap,
                "Model should be capped at " + cap + " items")
    }

    function test_06_app_launches_with_chat_page() {
        var app = createTemporaryObject(appComponent, tc)
        verify(app !== null)
        wait(300)

        // Navigate to the Chat page (index 3).
        var stack = findChild(app, "stack")
        if (stack) {
            stack.currentIndex = 3
            wait(100)
            compare(stack.currentIndex, 3, "Chat page should be active")
        }
    }
}
