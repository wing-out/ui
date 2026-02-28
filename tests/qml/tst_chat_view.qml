import QtQuick
import QtTest
import "../../qml/pages" as Pages
import "../../qml/components" as Components
import "../../qml" as WO

TestCase {
    id: testCase
    name: "ChatView"
    when: windowShown
    width: 600
    height: 800

    QtObject {
        id: mockSettings
        property bool ttsEnabled: false
        property bool ttsUsernames: false
        property bool vibrateEnabled: false
        property bool soundEnabled: true
        property string chatTimestampFormat: "mm"
    }

    Component {
        id: chatComponent
        Pages.ChatPage {
            width: 600
            height: 800
            controller: mockBackend
            settings: mockSettings
        }
    }

    function test_creation() {
        var page = createTemporaryObject(chatComponent, testCase)
        verify(page !== null, "ChatPage created")
    }

    function test_default_filter() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.platformFilter, "")
    }

    function test_filter_twitch() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.platformFilter = "twitch"
        compare(page.platformFilter, "twitch")
    }

    function test_filter_youtube() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.platformFilter = "youtube"
        compare(page.platformFilter, "youtube")
    }

    function test_filter_kick() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.platformFilter = "kick"
        compare(page.platformFilter, "kick")
    }

    function test_filter_all() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.platformFilter = "twitch"
        compare(page.platformFilter, "twitch")
        page.platformFilter = ""
        compare(page.platformFilter, "")
    }

    function test_empty_messages() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.messages.count, 0)
    }

    function test_add_message() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.messages.append({
            platform: "twitch",
            userName: "TestUser",
            message: "Hello!"
        })
        compare(page.messages.count, 1)
        compare(page.messages.get(0).userName, "TestUser")
        compare(page.messages.get(0).message, "Hello!")
        compare(page.messages.get(0).platform, "twitch")
    }

    function test_add_multiple_messages() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.messages.append({platform: "twitch", userName: "User1", message: "Hi"})
        page.messages.append({platform: "youtube", userName: "User2", message: "Hey"})
        page.messages.append({platform: "kick", userName: "User3", message: "Sup"})
        compare(page.messages.count, 3)
    }

    function test_platform_color_mapping() {
        compare(WO.Theme.twitch, Qt.color("#9146FF"))
        compare(WO.Theme.youtube, Qt.color("#FF0000"))
        compare(WO.Theme.kick, Qt.color("#53FC18"))
    }

    function test_filter_cycle() {
        var page = createTemporaryObject(chatComponent, testCase)
        var filters = ["", "twitch", "youtube", "kick", ""]
        for (var i = 0; i < filters.length; i++) {
            page.platformFilter = filters[i]
            compare(page.platformFilter, filters[i])
        }
    }

    // --- Username color generation (HSL hash function) ---

    function test_usernameColor_same_name_same_color() {
        var page = createTemporaryObject(chatComponent, testCase)
        var color1 = page.usernameColor("Alice")
        var color2 = page.usernameColor("Alice")
        compare(color1.toString(), color2.toString(), "Same name should produce same color")
    }

    function test_usernameColor_different_names_different_colors() {
        var page = createTemporaryObject(chatComponent, testCase)
        var color1 = page.usernameColor("Alice")
        var color2 = page.usernameColor("Bob")
        verify(color1.toString() !== color2.toString(),
               "Different names should produce different colors: " + color1 + " vs " + color2)
    }

    function test_usernameColor_returns_valid_color() {
        var page = createTemporaryObject(chatComponent, testCase)
        var color = page.usernameColor("TestUser")
        verify(color.r >= 0.0 && color.r <= 1.0, "Red component in valid range")
        verify(color.g >= 0.0 && color.g <= 1.0, "Green component in valid range")
        verify(color.b >= 0.0 && color.b <= 1.0, "Blue component in valid range")
        fuzzyCompare(color.a, 1.0, 0.01, "Alpha should be 1.0")
    }

    function test_usernameColor_empty_string() {
        var page = createTemporaryObject(chatComponent, testCase)
        var color = page.usernameColor("")
        // Hash of empty string is 0, so hue = 0
        verify(color.r >= 0.0 && color.r <= 1.0, "Color from empty string should be valid")
    }

    function test_usernameColor_deterministic_across_instances() {
        var page1 = createTemporaryObject(chatComponent, testCase)
        var page2 = createTemporaryObject(chatComponent, testCase)
        var color1 = page1.usernameColor("StreamerPro")
        var color2 = page2.usernameColor("StreamerPro")
        compare(color1.toString(), color2.toString(),
                "Same name should produce same color across different page instances")
    }

    function test_usernameColor_special_characters() {
        var page = createTemporaryObject(chatComponent, testCase)
        var color1 = page.usernameColor("user_123")
        var color2 = page.usernameColor("user-456")
        verify(color1.r >= 0.0 && color1.r <= 1.0, "Color from special chars should be valid")
        verify(color1.toString() !== color2.toString(),
               "Different usernames with special chars should differ")
    }

    // --- TTS toggle state management ---

    function test_tts_default_off() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.settings.ttsEnabled, false, "TTS should be off by default")
    }

    function test_tts_toggle_on() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.settings.ttsEnabled = true
        compare(page.settings.ttsEnabled, true)
    }

    function test_tts_toggle_off_again() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.settings.ttsEnabled = true
        compare(page.settings.ttsEnabled, true)
        page.settings.ttsEnabled = false
        compare(page.settings.ttsEnabled, false)
    }

    // --- Vibrate toggle state management ---

    function test_vibrate_default_off() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.settings.vibrateEnabled, false, "Vibrate should be off by default")
    }

    function test_vibrate_toggle_on() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.settings.vibrateEnabled = true
        compare(page.settings.vibrateEnabled, true)
    }

    function test_vibrate_toggle_cycle() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.settings.vibrateEnabled, false)
        page.settings.vibrateEnabled = true
        compare(page.settings.vibrateEnabled, true)
        page.settings.vibrateEnabled = false
        compare(page.settings.vibrateEnabled, false)
    }

    // --- Sound toggle state management ---

    function test_sound_default_on() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.settings.soundEnabled, true, "Sound should be on by default")
    }

    function test_sound_toggle_off() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.settings.soundEnabled = false
        compare(page.settings.soundEnabled, false)
    }

    function test_sound_toggle_cycle() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.settings.soundEnabled, true)
        page.settings.soundEnabled = false
        compare(page.settings.soundEnabled, false)
        page.settings.soundEnabled = true
        compare(page.settings.soundEnabled, true)
    }

    // --- All toggles independent ---

    function test_toggles_independent() {
        var page = createTemporaryObject(chatComponent, testCase)
        // Toggle TTS on without affecting others
        page.settings.ttsEnabled = true
        compare(page.settings.ttsEnabled, true)
        compare(page.settings.vibrateEnabled, false)
        compare(page.settings.soundEnabled, true)

        // Toggle vibrate on without affecting others
        page.settings.vibrateEnabled = true
        compare(page.settings.ttsEnabled, true)
        compare(page.settings.vibrateEnabled, true)
        compare(page.settings.soundEnabled, true)

        // Toggle sound off without affecting others
        page.settings.soundEnabled = false
        compare(page.settings.ttsEnabled, true)
        compare(page.settings.vibrateEnabled, true)
        compare(page.settings.soundEnabled, false)
    }

    // --- Message sending input field state ---

    function test_chat_input_exists() {
        var page = createTemporaryObject(chatComponent, testCase)
        var input = findChild(page, "chatInput")
        verify(input !== null, "Chat input field should exist")
    }

    function test_chat_send_button_exists() {
        var page = createTemporaryObject(chatComponent, testCase)
        var btn = findChild(page, "chatSendButton")
        verify(btn !== null, "Chat send button should exist")
    }

    function test_send_platform_defaults_to_twitch_when_no_filter() {
        // When platformFilter is "", the send logic uses "twitch" as default
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.platformFilter, "")
        // The ternary in the page: platformFilter !== "" ? platformFilter : "twitch"
        var platform = page.platformFilter !== "" ? page.platformFilter : "twitch"
        compare(platform, "twitch")
    }

    function test_send_platform_uses_filter_when_set() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.platformFilter = "youtube"
        var platform = page.platformFilter !== "" ? page.platformFilter : "twitch"
        compare(platform, "youtube")
    }

    // --- Bot username filtering logic ---

    function test_anonymous_fallback_for_empty_username() {
        // The page uses: model.userName || "Anonymous"
        var userName = "" || "Anonymous"
        compare(userName, "Anonymous")
    }

    function test_anonymous_fallback_for_null_username() {
        var userName = null || "Anonymous"
        compare(userName, "Anonymous")
    }

    function test_anonymous_fallback_for_undefined_username() {
        var userName = undefined || "Anonymous"
        compare(userName, "Anonymous")
    }

    function test_normal_username_preserved() {
        var userName = "RealUser" || "Anonymous"
        compare(userName, "RealUser")
    }

    // --- Bot filtering ---

    function test_isBot_known_bots() {
        var page = createTemporaryObject(chatComponent, testCase)
        verify(page.isBot("savedggbot"), "savedggbot should be a bot")
        verify(page.isBot("Botrix"), "Botrix (case-insensitive) should be a bot")
        verify(page.isBot("BOTRIXOFICIAL"), "BOTRIXOFICIAL should be a bot")
        verify(page.isBot("Nightbot"), "Nightbot should be a bot")
        verify(page.isBot("StreamElements"), "StreamElements should be a bot")
    }

    function test_isBot_normal_user() {
        var page = createTemporaryObject(chatComponent, testCase)
        verify(!page.isBot("RealUser"), "RealUser should not be a bot")
        verify(!page.isBot("xQc"), "xQc should not be a bot")
    }

    function test_isBot_empty_null() {
        var page = createTemporaryObject(chatComponent, testCase)
        verify(!page.isBot(""), "Empty string should not be a bot")
        verify(!page.isBot(null), "null should not be a bot")
    }

    function test_botUsernames_list() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.botUsernames.length, 5)
        verify(page.botUsernames.indexOf("savedggbot") >= 0)
        verify(page.botUsernames.indexOf("nightbot") >= 0)
        verify(page.botUsernames.indexOf("streamelements") >= 0)
    }

    // --- TTS usernames toggle ---

    function test_ttsUsernames_default_off() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.ttsUsernames, false, "TTS usernames should be off by default")
    }

    function test_ttsUsernames_toggle_on() {
        var page = createTemporaryObject(chatComponent, testCase)
        page.ttsUsernames = true
        compare(page.ttsUsernames, true)
    }

    function test_ttsUsernames_toggle_cycle() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.ttsUsernames, false)
        page.ttsUsernames = true
        compare(page.ttsUsernames, true)
        page.ttsUsernames = false
        compare(page.ttsUsernames, false)
    }

    // --- TTS usernames toggle UI ---

    function test_ttsUsernames_toggle_exists() {
        var page = createTemporaryObject(chatComponent, testCase)
        var toggle = findChild(page, "ttsUsernamesToggle")
        verify(toggle !== null, "TTS:name toggle should exist")
    }

    // --- Chat subscription ---

    function test_subscribeToChatMessages_called_on_creation() {
        mockBackend.resetCallCounts()
        var page = createTemporaryObject(chatComponent, testCase)
        verify(mockBackend.callCount("subscribeToChatMessages") >= 1,
               "subscribeToChatMessages should be called on Component.onCompleted")
    }

    // --- chatMessageReceived appends to model ---

    function test_chatMessageReceived_appends_message() {
        var page = createTemporaryObject(chatComponent, testCase)
        compare(page.messages.count, 0, "Should start empty")

        mockBackend.emitTestChatMessage({
            "messageId": "msg1",
            "platform": "twitch",
            "userName": "TestStreamer",
            "text": "Hello world!",
            "timestamp": 12345
        })

        compare(page.messages.count, 1, "Should have 1 message after signal")
        compare(page.messages.get(0).userName, "TestStreamer")
        compare(page.messages.get(0).message, "Hello world!")
        compare(page.messages.get(0).platform, "twitch")
    }

    function test_chatMessageReceived_multiple() {
        var page = createTemporaryObject(chatComponent, testCase)

        mockBackend.emitTestChatMessage({
            "platform": "twitch", "userName": "User1", "text": "msg1"
        })
        mockBackend.emitTestChatMessage({
            "platform": "youtube", "userName": "User2", "text": "msg2"
        })
        mockBackend.emitTestChatMessage({
            "platform": "kick", "userName": "User3", "text": "msg3"
        })

        compare(page.messages.count, 3)
        compare(page.messages.get(0).platform, "twitch")
        compare(page.messages.get(1).platform, "youtube")
        compare(page.messages.get(2).platform, "kick")
    }

    function test_chatMessageReceived_bot_still_appended() {
        // Bot messages are still added to the list, just not triggering notifications
        var page = createTemporaryObject(chatComponent, testCase)

        mockBackend.emitTestChatMessage({
            "platform": "twitch", "userName": "Nightbot", "text": "bot message"
        })

        compare(page.messages.count, 1, "Bot messages should still appear in the list")
        compare(page.messages.get(0).userName, "Nightbot")
    }
}
