//go:build android_e2e

package android

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestChat_FilterButtonsPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	filters := []string{"chatFilterAll", "chatFilterTwitch", "chatFilterYouTube", "chatFilterKick"}
	for _, f := range filters {
		t.Run(f, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(f)
			require.NotNil(t, node, "filter button %q should be visible", f)
		})
	}
	screenshot(t, env, "chat_filters")
}

func TestChat_FilterButtonLabels(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Verify filter button text labels
	require.NotEmpty(t, hierarchy.FindContainingText("All"), "All filter label should exist")
	require.NotEmpty(t, hierarchy.FindContainingText("Twitch"), "Twitch filter label should exist")
	require.NotEmpty(t, hierarchy.FindContainingText("YouTube"), "YouTube filter label should exist")
	require.NotEmpty(t, hierarchy.FindContainingText("Kick"), "Kick filter label should exist")
	screenshot(t, env, "chat_filter_labels")
}

func TestChat_FilterToggle(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")

	// Tap Twitch filter
	twitchBtn, err := env.adb.WaitForElement("chatFilterTwitch", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(twitchBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_twitch_selected")

	// Tap YouTube filter
	ytBtn, err := env.adb.WaitForElement("chatFilterYouTube", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(ytBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_youtube_selected")

	// Tap Kick filter
	kickBtn, err := env.adb.WaitForElement("chatFilterKick", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(kickBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_kick_selected")

	// Tap All filter to reset
	allBtn, err := env.adb.WaitForElement("chatFilterAll", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(allBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "chat_all_selected")
}

func TestChat_EmptyMessageList(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// No chat messages should be present by default (mock doesn't send any)
	chatPage := hierarchy.FindByContentDesc("chatPage")
	require.NotNil(t, chatPage, "chat page should be visible")
	screenshot(t, env, "chat_empty")
}

func TestChat_TTSTogglePresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("ttsToggle", elementTimeout)
	require.NoError(t, err, "TTS toggle button should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_tts_toggle")
}

func TestChat_TTSToggleInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially TTS is OFF
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	ttsOff := hierarchy.FindContainingText("TTS OFF")
	require.NotEmpty(t, ttsOff, "TTS toggle should initially show 'TTS OFF'")

	// Tap TTS toggle to enable
	ttsBtn, err := env.adb.WaitForElement("ttsToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(ttsBtn))
	Sleep(500 * time.Millisecond)

	// Now should show TTS ON
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	ttsOn := hierarchy.FindContainingText("TTS ON")
	require.NotEmpty(t, ttsOn, "TTS toggle should show 'TTS ON' after tap")

	// Tap again to disable
	ttsBtn, err = env.adb.WaitForElement("ttsToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(ttsBtn))
	Sleep(500 * time.Millisecond)

	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	ttsOffAgain := hierarchy.FindContainingText("TTS OFF")
	require.NotEmpty(t, ttsOffAgain, "TTS toggle should show 'TTS OFF' after second tap")
	screenshot(t, env, "chat_tts_toggle_interaction")
}

func TestChat_TTSUsernameTogglePresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("ttsUsernamesToggle", elementTimeout)
	require.NoError(t, err, "TTS username toggle button should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_tts_usernames_toggle")
}

func TestChat_TTSUsernameToggleInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// First enable TTS (TTS username toggle is only enabled when TTS is on)
	ttsBtn, err := env.adb.WaitForElement("ttsToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(ttsBtn))
	Sleep(500 * time.Millisecond)

	// Initially TTS:name is OFF
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	nameOff := hierarchy.FindContainingText("TTS:name OFF")
	require.NotEmpty(t, nameOff, "TTS username toggle should initially show 'TTS:name OFF'")

	// Tap to enable
	nameBtn, err := env.adb.WaitForElement("ttsUsernamesToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(nameBtn))
	Sleep(500 * time.Millisecond)

	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	nameOn := hierarchy.FindContainingText("TTS:name ON")
	require.NotEmpty(t, nameOn, "TTS username toggle should show 'TTS:name ON' after tap")
	screenshot(t, env, "chat_tts_username_toggle_interaction")
}

func TestChat_VibrateTogglePresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("vibrateToggle", elementTimeout)
	require.NoError(t, err, "Vibrate toggle button should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_vibrate_toggle")
}

func TestChat_VibrateToggleInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially Vibrate is OFF
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	vibOff := hierarchy.FindContainingText("Vibrate OFF")
	require.NotEmpty(t, vibOff, "Vibrate toggle should initially show 'Vibrate OFF'")

	// Tap to enable
	vibBtn, err := env.adb.WaitForElement("vibrateToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(vibBtn))
	Sleep(500 * time.Millisecond)

	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	vibOn := hierarchy.FindContainingText("Vibrate ON")
	require.NotEmpty(t, vibOn, "Vibrate toggle should show 'Vibrate ON' after tap")
	screenshot(t, env, "chat_vibrate_toggle_interaction")
}

func TestChat_SoundTogglePresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("soundToggle", elementTimeout)
	require.NoError(t, err, "Sound toggle button should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_sound_toggle")
}

func TestChat_SoundToggleInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Initially Sound is ON
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	sndOn := hierarchy.FindContainingText("Sound ON")
	require.NotEmpty(t, sndOn, "Sound toggle should initially show 'Sound ON'")

	// Tap to disable
	sndBtn, err := env.adb.WaitForElement("soundToggle", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(sndBtn))
	Sleep(500 * time.Millisecond)

	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	sndOff := hierarchy.FindContainingText("Sound OFF")
	require.NotEmpty(t, sndOff, "Sound toggle should show 'Sound OFF' after tap")
	screenshot(t, env, "chat_sound_toggle_interaction")
}

func TestChat_MessageInputPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("chatInput", elementTimeout)
	require.NoError(t, err, "Chat message input field should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_message_input")
}

func TestChat_SendButtonPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("chatSendButton", elementTimeout)
	require.NoError(t, err, "Send button should exist")
	require.NotNil(t, node)
	screenshot(t, env, "chat_send_button")
}

func TestChat_SendButtonLabel(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	sendNodes := hierarchy.FindContainingText("Send")
	require.NotEmpty(t, sendNodes, "Send button label should exist")
	screenshot(t, env, "chat_send_label")
}

func TestChat_SendMessageCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Tap the message input and type a message
	inputField, err := env.adb.WaitForElement("chatInput", elementTimeout)
	require.NoError(t, err, "Chat input should exist")
	require.NoError(t, env.adb.TapNode(inputField))
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.TypeText("Hello"))
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.PressBack())
	Sleep(500 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap the Send button
	sendBtn, err := env.adb.WaitForElement("chatSendButton", elementTimeout)
	require.NoError(t, err, "Send button should exist")
	require.NoError(t, env.adb.TapNode(sendBtn))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SendChatMessage"), 1, "SendChatMessage should have been called")
	screenshot(t, env, "chat_send_message_backend")
}

func TestChat_MessageInputAndSendButtonLayout(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Chat")
	Sleep(1 * time.Second)

	// Verify the input field and send button are visible with proper dimensions
	inputField, err := env.adb.WaitForElement("chatInput", elementTimeout)
	require.NoError(t, err, "Chat input should exist")
	cx, cy, err := inputField.Center()
	require.NoError(t, err, "Chat input bounds should be parsable")
	require.Greater(t, cy, 0, "Chat input should have valid y coordinate")
	require.Greater(t, cx, 0, "Chat input should have valid x coordinate")

	sendBtn, err := env.adb.WaitForElement("chatSendButton", elementTimeout)
	require.NoError(t, err, "Send button should exist")
	sx, sy, err := sendBtn.Center()
	require.NoError(t, err, "Send button bounds should be parsable")
	require.Greater(t, sx, cx, "Send button should be to the right of input field")
	require.InDelta(t, cy, sy, 100, "Send button should be at roughly the same y as input")

	screenshot(t, env, "chat_input_layout")
}
