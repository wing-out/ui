//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_ChatFilterButtonLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("All"), "'All' filter button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Twitch"), "'Twitch' filter button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("YouTube"), "'YouTube' filter button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Kick"), "'Kick' filter button label should be visible")
	screenshot(t, env, "chat_filter_labels")
}

func TestDesktop_ChatPageLoads(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	node, err := env.atspi.WaitForElement("chatPage", elementTimeout)
	require.NoError(t, err, "chat page should be visible")
	require.NotNil(t, node)
	screenshot(t, env, "chat_page")
}

func TestDesktop_ChatFilterButtons(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	filters := []string{"chatFilterAll", "chatFilterTwitch", "chatFilterYouTube", "chatFilterKick"}
	for _, f := range filters {
		t.Run(f, func(t *testing.T) {
			node := tree.FindByName(f)
			require.NotNil(t, node, "filter button %q should be visible", f)
		})
	}
	screenshot(t, env, "chat_filters")
}

func TestDesktop_ChatToggleButtons(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	toggles := []string{"ttsToggle", "vibrateToggle", "soundToggle"}
	for _, toggle := range toggles {
		t.Run(toggle, func(t *testing.T) {
			node := tree.FindByName(toggle)
			require.NotNil(t, node, "toggle button %q should be visible", toggle)
		})
	}
	screenshot(t, env, "chat_toggles")
}

func TestDesktop_ChatFilterToggle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	// Tap each filter in succession
	require.NoError(t, env.atspi.ActivateByName("chatFilterTwitch"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_twitch_selected")

	require.NoError(t, env.atspi.ActivateByName("chatFilterYouTube"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_youtube_selected")

	require.NoError(t, env.atspi.ActivateByName("chatFilterKick"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_kick_selected")

	require.NoError(t, env.atspi.ActivateByName("chatFilterAll"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_all_selected")
}

func TestDesktop_ChatEmptyMessages(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// No chat messages by default (mock doesn't send any)
	chatPage := tree.FindByName("chatPage")
	require.NotNil(t, chatPage, "chat page should be visible")
	screenshot(t, env, "chat_empty")
}

func TestDesktop_ChatInputAndSendButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	input := tree.FindByName("chatInput")
	require.NotNil(t, input, "chat input field should be visible")

	sendBtn := tree.FindByName("chatSendButton")
	require.NotNil(t, sendBtn, "chat send button should be visible")
	screenshot(t, env, "chat_input_send")
}

func TestDesktop_ChatTTSToggleInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially TTS is off
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	offNodes := tree.FindContainingText("TTS OFF")
	require.NotEmpty(t, offNodes, "TTS toggle should initially show 'TTS OFF'")

	// Tap to enable TTS
	require.NoError(t, env.atspi.ActivateByName("ttsToggle"))
	Sleep(500 * time.Millisecond)

	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)
	onNodes := tree.FindContainingText("TTS ON")
	require.NotEmpty(t, onNodes, "TTS toggle should show 'TTS ON' after tapping")

	// Tap to disable TTS
	require.NoError(t, env.atspi.ActivateByName("ttsToggle"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_tts_toggle")
}

func TestDesktop_ChatTTSUsernameTogglePresent(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	toggle := tree.FindByName("ttsUsernamesToggle")
	require.NotNil(t, toggle, "TTS usernames toggle should be present")
	screenshot(t, env, "chat_tts_username_toggle")
}

func TestDesktop_ChatTTSUsernameToggleInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Enable TTS first
	require.NoError(t, env.atspi.ActivateByName("ttsToggle"))
	Sleep(500 * time.Millisecond)

	// Toggle username reading
	require.NoError(t, env.atspi.ActivateByName("ttsUsernamesToggle"))
	Sleep(500 * time.Millisecond)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	nameNodes := tree.FindContainingText("Name ON")
	require.NotEmpty(t, nameNodes, "TTS username toggle should show 'Name ON' after tapping")

	// Toggle back
	require.NoError(t, env.atspi.ActivateByName("ttsUsernamesToggle"))
	Sleep(500 * time.Millisecond)

	// Disable TTS
	require.NoError(t, env.atspi.ActivateByName("ttsToggle"))
	Sleep(300 * time.Millisecond)
	screenshot(t, env, "chat_tts_username_interaction")
}

func TestDesktop_ChatVibrateToggleInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially vibrate is off
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	offNodes := tree.FindContainingText("Vibrate OFF")
	require.NotEmpty(t, offNodes, "Vibrate toggle should initially show 'Vibrate OFF'")

	// Tap to enable
	require.NoError(t, env.atspi.ActivateByName("vibrateToggle"))
	Sleep(500 * time.Millisecond)

	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)
	onNodes := tree.FindContainingText("Vibrate ON")
	require.NotEmpty(t, onNodes, "Vibrate toggle should show 'Vibrate ON' after tapping")

	// Tap to disable
	require.NoError(t, env.atspi.ActivateByName("vibrateToggle"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_vibrate_toggle")
}

func TestDesktop_ChatSoundToggleInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially sound is on
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	onNodes := tree.FindContainingText("Sound ON")
	require.NotEmpty(t, onNodes, "Sound toggle should initially show 'Sound ON'")

	// Tap to disable
	require.NoError(t, env.atspi.ActivateByName("soundToggle"))
	Sleep(500 * time.Millisecond)

	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)
	offNodes := tree.FindContainingText("Sound OFF")
	require.NotEmpty(t, offNodes, "Sound toggle should show 'Sound OFF' after tapping")

	// Tap to re-enable
	require.NoError(t, env.atspi.ActivateByName("soundToggle"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_sound_toggle")
}

func TestDesktop_ChatSendButtonLabel(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	sendNodes := tree.FindContainingText("Send")
	require.NotEmpty(t, sendNodes, "'Send' button label should be visible")
	screenshot(t, env, "chat_send_label")
}

func TestDesktop_ChatMessageInputTypable(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Activate the input field
	require.NoError(t, env.atspi.ActivateByName("chatInput"))
	Sleep(300 * time.Millisecond)

	// Type a message
	require.NoError(t, env.atspi.TypeText("Hello from E2E test"))
	Sleep(500 * time.Millisecond)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	msgNodes := tree.FindContainingText("Hello from E2E test")
	require.NotEmpty(t, msgNodes, "typed message should be visible in chat input")
	screenshot(t, env, "chat_message_typed")
}

func TestDesktop_ChatSendCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Type a message
	require.NoError(t, env.atspi.ActivateByName("chatInput"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("test message"))
	Sleep(300 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap send
	require.NoError(t, env.atspi.ActivateByName("chatSendButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SendChatMessage"), 1,
		"SendChatMessage should have been called after tapping Send")
	screenshot(t, env, "chat_send_backend")
}
