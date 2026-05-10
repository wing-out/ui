import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtTest
import QtCore as Core
import WingOut

/// E2E verification of the Dashboard CheckBox UI change. The full Application
/// crashes during load on this build (pre-existing Qt6 multimedia FFmpeg
/// SIGSEGV when two MediaPlayers initialise simultaneously — also reproduces
/// in tst_application_flow), so we render the Dashboard.qml component with a
/// mocked `root` that satisfies its required properties. We assert the three
/// Music / Subs / Sound controls expose the QtQuick.Controls 2 CheckBox
/// `nextCheckState` callback (Button does not), and that toggling Sound flips
/// `checked`. A best-effort screenshot is also captured to
/// /tmp/wingout-checkboxes.png for visual review, but its success is not part
/// of the pass criteria.
TestCase {
    id: tc
    name: "DashboardCheckboxes"
    when: windowShown
    width: 1080
    height: 1920
    visible: true

    // Mock objects exposing only the methods/properties Dashboard touches.
    QtObject {
        id: stubAppSettings
        property bool soundEnabled: false
        property string previewRTMPUrl: ""
        property string dxProducerHost: "https://localhost:1234"
        property string ffstreamHost: ""
    }

    QtObject {
        id: stubGrpcCallOptions
    }

    QtObject {
        id: stubClient
        function ping() {}
        function getLatencies() {}
        function getInputQuality() {}
        function getFPSFraction() {}
        function getOutputQuality() {}
        function getBitRates() {}
        function getPlayerLag() {}
        function listStreamPlayers() {}
        function subscribeToChatMessages() {}
        function setVariable(name, value, ok, err, opts) { /* no-op */ }
        function getVariable(name, ok, err, opts) { /* no-op */ }
        function getBackendInfo() {}
        function banUser() {}
        function listProfiles() {}
        function listStreamSources() {}
        function listStreamServers() {}
        function reconnect() {}
        property var processGRPCError: undefined
    }

    ListModel {
        id: stubChatModel
    }

    QtObject {
        id: stubPlatform
        // ChatView's onRowsInserted calls root.platform.vibrate when
        // vibrateEnabled is true. Provide a no-op so test message inserts
        // do not crash.
        function vibrate(ms, hard) { /* no-op */ }
    }

    QtObject {
        id: stubRoot
        property var appSettings: stubAppSettings
        property var dxProducerClient: stubClient
        property var ffstreamClient: stubClient
        property var grpcCallOptions: stubGrpcCallOptions
        property var streamingGrpcCallOptions: stubGrpcCallOptions
        property var globalChatMessagesModel: stubChatModel
        property string dxProducerHost: "https://localhost:1234"
        property var platform: stubPlatform
        function processStreamDGRPCError() {}
        function processFFStreamGRPCError() {}
        function checkStreamDClient() { return false } // disables RPC paths
        function fireMultiPlatformRPC() {}
        property var platformCapabilities: ({})
    }

    Component {
        id: dashboardComp
        Dashboard {
            anchors.fill: parent
            root: stubRoot
            platformCapabilities: ({})
        }
    }

    function test_capture_dashboard_checkboxes() {
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null, "Dashboard must instantiate")

        // Allow Dashboard to render. checkStreamDClient() returns false so
        // RPC paths short-circuit and no MediaPlayer is wired to a live URL.
        wait(800)

        // Discriminator: object exposes the QtQuick.Controls 2 CheckBox 'checkState' property (Button does not).
        function findControlByText(root, label) {
            if (!root) return null
            if (typeof root.text !== "undefined" && root.text === label
                && typeof root.checkState !== "undefined") {
                return root
            }
            for (var i = 0; i < (root.children ? root.children.length : 0); i++) {
                var hit = findControlByText(root.children[i], label)
                if (hit) return hit
            }
            return null
        }
        var musicCb = findControlByText(dashboard, "Music")
        var subsCb  = findControlByText(dashboard, "Subs")
        var soundCb = findControlByText(dashboard, "Sound")
        verify(musicCb !== null, "Music must be a CheckBox")
        verify(subsCb  !== null, "Subs must be a CheckBox")
        verify(soundCb !== null, "Sound must be a CheckBox")

        // Use click() not toggle(): toggle() bypasses nextCheckState so it
        // would not write appSettings. Observe gating via chatView.soundEnabled.
        var chatViewInstance = findChild(dashboard, "chatView")
        verify(chatViewInstance !== null, "ChatView instance must exist for sound-gating verification")

        var beforeSound = soundCb.checked
        var beforeChatViewSound = chatViewInstance.soundEnabled
        soundCb.click()
        wait(50)
        var afterSound = soundCb.checked
        verify(beforeSound !== afterSound, "Sound CheckBox click must flip checked state")
        verify(chatViewInstance.soundEnabled !== beforeChatViewSound,
               "Sound click must propagate to ChatView.soundEnabled — this is the gating signal that suppresses chat-message sound")
        compare(chatViewInstance.soundEnabled, afterSound,
                "ChatView.soundEnabled must track checkbox checked state after click")

        // Restore Sound to a checked state for the screenshot.
        if (!soundCb.checked) {
            soundCb.click()
            wait(50)
        }

        // Best-effort screenshot for visual review. NOT part of pass criteria —
        // failure to write the PNG (e.g. /tmp not writable, headless GPU
        // limitations) must not fail the test; the CheckBox assertions above
        // are the actual contract.
        var captured = false
        var ok = tc.grabToImage(function(result) {
            var saved = result.saveToFile("/tmp/wingout-checkboxes.png")
            console.log("tst_dashboard_checkboxes: grabToImage saveToFile -> " + saved)
            captured = true
        })
        if (ok) {
            tryVerify(function() { return captured }, 5000,
                      "Screenshot scheduled but never completed")
        }
    }

    // SignalSpy attached to ChatView.chatSoundPlayed; the spy is rebound to a
    // freshly constructed Dashboard's ChatView at the start of the test.
    SignalSpy {
        id: chatSoundSpy
        signalName: "chatSoundPlayed"
    }

    function test_sound_checkbox_gates_chat_message_play() {
        // Independent Dashboard instance for this test so we do not depend on
        // ordering with respect to test_capture_dashboard_checkboxes.
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null, "Dashboard must instantiate")
        wait(800)

        function findControlByText(root, label) {
            if (!root) return null
            if (typeof root.text !== "undefined" && root.text === label
                && typeof root.checkState !== "undefined") {
                return root
            }
            for (var i = 0; i < (root.children ? root.children.length : 0); i++) {
                var hit = findControlByText(root.children[i], label)
                if (hit) return hit
            }
            return null
        }

        var soundCb = findControlByText(dashboard, "Sound")
        verify(soundCb !== null, "Sound CheckBox must exist")

        var chatViewInstance = findChild(dashboard, "chatView")
        verify(chatViewInstance !== null, "ChatView instance must exist")

        // Bind the spy to the ChatView's chatSoundPlayed signal. We assert
        // signal-emission counts, not Qt Multimedia playback state, because
        // QSoundEffect/playingChanged is unreliable under offscreen+FFmpeg.
        chatSoundSpy.target = chatViewInstance
        verify(chatSoundSpy.valid, "chatSoundPlayed signal must exist on ChatView")

        // Step 1: ensure Sound is enabled. stubAppSettings.soundEnabled starts
        // false; one click flips it to true via the CheckBox nextCheckState
        // path, exercising the same chain a user clicks.
        if (!soundCb.checked) {
            soundCb.click()
            wait(50)
        }
        verify(soundCb.checked, "Precondition: Sound CheckBox must be checked")
        compare(chatViewInstance.soundEnabled, true,
                "Precondition: chatView.soundEnabled must reflect enabled state")

        // Step 2: simulate a chat message arriving. The model is the stub
        // ListModel referenced by Dashboard via root.globalChatMessagesModel.
        // Use a non-bot username and isLive=true so onRowsInserted does not
        // early-return.
        chatSoundSpy.clear()
        stubChatModel.append({
            timestamp: "1",
            platformName: "twitch",
            eventType: 1,
            username: "alice",
            usernameReadable: "Alice",
            message: "hello",
            messageFormatType: 1,
            isTest: false,
            eventID: "e1",
            userID: "u1",
            moneyAmount: 0,
            moneyCurrency: 0,
            isDeleted: false,
            isLive: true
        })
        wait(50)
        compare(chatSoundSpy.count, 1,
                "When soundEnabled=true a chat message must trigger soundAddChatMessage.play() exactly once")

        // Step 3: disable sound via a real CheckBox click (NOT toggle()).
        soundCb.click()
        wait(50)
        verify(!soundCb.checked, "Sound CheckBox must be unchecked after disable click")
        compare(chatViewInstance.soundEnabled, false,
                "chatView.soundEnabled must follow appSettings.soundEnabled after click")

        // Step 4: simulate another chat message; signal must NOT fire.
        var countBeforeSuppressed = chatSoundSpy.count
        stubChatModel.append({
            timestamp: "2",
            platformName: "twitch",
            eventType: 1,
            username: "bob",
            usernameReadable: "Bob",
            message: "world",
            messageFormatType: 1,
            isTest: false,
            eventID: "e2",
            userID: "u2",
            moneyAmount: 0,
            moneyCurrency: 0,
            isDeleted: false,
            isLive: true
        })
        wait(50)
        compare(chatSoundSpy.count, countBeforeSuppressed,
                "When soundEnabled=false (after CheckBox click) a chat message must NOT trigger soundAddChatMessage.play()")
    }

    // ---------------------------------------------------------------
    // Helpers shared by the focused gating tests below.
    // ---------------------------------------------------------------
    function _findCheckBoxByText(node, label) {
        if (!node) return null
        if (typeof node.text !== "undefined" && node.text === label
            && typeof node.checkState !== "undefined") {
            return node
        }
        for (var i = 0; i < (node.children ? node.children.length : 0); i++) {
            var hit = _findCheckBoxByText(node.children[i], label)
            if (hit) return hit
        }
        return null
    }

    // Drive a CheckBox to a target state with at most one click. Necessary
    // because the production Dashboard binds Sound to a Core.Settings-backed
    // property whose value persists across createTemporaryObject recreations
    // via QSettings. Tests that assume a clean start would otherwise be
    // order-dependent and flaky; this helper makes them deterministic.
    function _driveCheckTo(cb, want) {
        if (cb.checked !== want) {
            cb.click()
            wait(50)
        }
        verify(cb.checked === want,
               "_driveCheckTo: failed to drive checkbox to " + want)
    }

    function _appendChat(model, opts) {
        // Default values that exercise the non-bot, isLive=true happy path
        // (same shape as Dashboard's globalChatMessagesModel rows).
        var row = {
            timestamp: opts.timestamp || "1",
            platformName: opts.platformName || "twitch",
            eventType: 1,
            username: opts.username,
            usernameReadable: opts.usernameReadable || opts.username,
            message: opts.message || "msg",
            messageFormatType: 1,
            isTest: false,
            eventID: opts.eventID || "e",
            userID: opts.userID || "u",
            moneyAmount: 0,
            moneyCurrency: 0,
            isDeleted: false,
            isLive: typeof opts.isLive === "boolean" ? opts.isLive : true
        }
        model.append(row)
    }

    SignalSpy {
        id: focusedSpy
        signalName: "chatSoundPlayed"
    }

    // (1) !isLive must NOT emit the chat sound, even when soundEnabled is true.
    function test_isLive_false_suppresses_sound_even_when_enabled() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance
        verify(focusedSpy.valid)
        _driveCheckTo(soundCb, true)
        compare(chatViewInstance.soundEnabled, true,
                "Pre: chatView.soundEnabled must be true")

        focusedSpy.clear()
        _appendChat(stubChatModel, { username: "alice", eventID: "x1", isLive: false })
        wait(50)
        compare(focusedSpy.count, 0,
                "Non-live chat row must not produce a sound, regardless of soundEnabled")
    }

    // (2) Bot usernames must NOT emit the chat sound (one test per bot, plus
    // case-insensitivity proof).
    function test_bot_usernames_are_silenced_when_sound_enabled() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance
        _driveCheckTo(soundCb, true)

        // Production switch lowercases the username; using mixed-case here
        // guarantees the .toLowerCase() branch is exercised.
        var bots = ["savedggbot", "Botrix", "BOTRIXOFICIAL"]
        for (var i = 0; i < bots.length; i++) {
            focusedSpy.clear()
            _appendChat(stubChatModel, { username: bots[i], eventID: "bot" + i })
            wait(50)
            compare(focusedSpy.count, 0,
                    "Bot username '" + bots[i] + "' must be silenced even when soundEnabled is true")
        }

        // Sanity: a non-bot under the same conditions DOES emit, proving the
        // suppression above was not an unrelated misconfiguration.
        focusedSpy.clear()
        _appendChat(stubChatModel, { username: "alice", eventID: "human" })
        wait(50)
        compare(focusedSpy.count, 1,
                "Non-bot row in same setup must emit — confirms test fixture is correct")
    }

    // (3) TTS path takes precedence over sound; chatSoundPlayed must NOT fire
    // even when soundEnabled is true.
    function test_tts_path_supersedes_sound_when_both_on() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var ttsCb = _findCheckBoxByText(dashboard, "TTS")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance
        _driveCheckTo(soundCb, true)

        // The TTS CheckBox is disabled when ttsAvailable is false (Qt's TTS
        // backend reports state==Error in some sandboxes). If TTS is not
        // available, this branch is unreachable for users either, so skip.
        if (!chatViewInstance.ttsAvailable) {
            skip("TextToSpeech reports Error state; TTS branch unreachable in this environment")
            return
        }
        if (!ttsCb.checked) {
            ttsCb.click()
            wait(50)
        }
        verify(ttsCb.checked, "Pre: TTS on")
        verify(chatViewInstance.ttsOn, "Pre: chatView.ttsOn")

        focusedSpy.clear()
        _appendChat(stubChatModel, { username: "alice", eventID: "tts1" })
        wait(50)
        compare(focusedSpy.count, 0,
                "When TTS is on, the chat sound must not also play (else-if branch)")
    }

    // (4) Repeated enable→disable→enable→disable toggle cycles. Each state
    // must gate correctly; off-state must never leak a sound through.
    function test_repeated_toggle_cycles_gate_correctly() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance
        _driveCheckTo(soundCb, true)

        // Start state: ON. Cycle ON→OFF→ON→OFF and assert one append per
        // state produces the expected count delta.
        var expectedTotal = 0
        var states = [true, false, true, false, true, false]
        for (var i = 0; i < states.length; i++) {
            // Drive checkbox to desired state via real click so we exercise
            // nextCheckState exactly like a user.
            if (soundCb.checked !== states[i]) {
                soundCb.click()
                wait(50)
            }
            compare(soundCb.checked, states[i], "checkbox state after cycle " + i)
            compare(chatViewInstance.soundEnabled, states[i],
                    "ChatView.soundEnabled propagation after cycle " + i)
            _appendChat(stubChatModel, { username: "u" + i, eventID: "cyc" + i })
            wait(50)
            if (states[i]) expectedTotal++
            compare(focusedSpy.count, expectedTotal,
                    "After cycle " + i + " (state=" + states[i] + ") signal count must be " + expectedTotal)
        }
    }

    // (5) Burst of messages while disabled. None should leak.
    function test_burst_messages_while_disabled_emit_zero() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance

        _driveCheckTo(soundCb, false)
        compare(chatViewInstance.soundEnabled, false)

        focusedSpy.clear()
        for (var i = 0; i < 25; i++) {
            _appendChat(stubChatModel, { username: "user" + i, eventID: "burst" + i })
        }
        wait(100)
        compare(focusedSpy.count, 0,
                "A burst of 25 chat messages while disabled must produce zero sound emissions")
    }

    // (6) Burst of messages while enabled — gating must not be over-zealous.
    // (Dual-sided assertion to detect a "fixed" version that simply suppresses
    // everything.)
    function test_burst_messages_while_enabled_emit_each() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance
        _driveCheckTo(soundCb, true)

        focusedSpy.clear()
        var N = 10
        for (var i = 0; i < N; i++) {
            _appendChat(stubChatModel, { username: "user" + i, eventID: "ok" + i })
        }
        wait(100)
        compare(focusedSpy.count, N,
                "All " + N + " chat messages while enabled must emit chatSoundPlayed")
    }

    // (7) Disabled state — verify that with soundEnabled=false at the
    // exact moment a row is appended, no sound fires. The Dashboard binds
    // Sound to a Core.Settings-backed property whose value persists across
    // process boundaries via QSettings, so we cannot reliably set a
    // pre-instantiation value from QML; we drive to the desired state
    // through clicks (the same code path a user takes), then append.
    function test_disabled_state_at_first_append_emits_no_sound() {
        stubChatModel.clear()
        var dashboard = createTemporaryObject(dashboardComp, tc)
        verify(dashboard !== null)
        wait(800)
        var soundCb = _findCheckBoxByText(dashboard, "Sound")
        var chatViewInstance = findChild(dashboard, "chatView")
        focusedSpy.target = chatViewInstance

        _driveCheckTo(soundCb, false)
        compare(chatViewInstance.soundEnabled, false,
                "Pre: chatView.soundEnabled must be false")

        focusedSpy.clear()
        _appendChat(stubChatModel, { username: "alice", eventID: "init" })
        wait(50)
        compare(focusedSpy.count, 0,
                "Message arriving while CheckBox is unchecked must not produce sound")
    }
}
