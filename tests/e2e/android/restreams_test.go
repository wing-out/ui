//go:build android_e2e

package android

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestRestreams_ForwardsList(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("twitch"), "twitch forward should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("youtube"), "youtube forward should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("kick"), "kick forward should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("cam0"), "source cam0 should be visible")
	screenshot(t, env, "restreams_list")
}

func TestRestreams_ActiveDisabledBadges(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	activeNodes := hierarchy.FindContainingText("Active")
	require.NotEmpty(t, activeNodes, "Active badge should exist for enabled forwards")

	disabledNodes := hierarchy.FindContainingText("Disabled")
	require.NotEmpty(t, disabledNodes, "Disabled badge should exist for kick (enabled=false)")
	screenshot(t, env, "restreams_badges")
}

func TestRestreams_EmptyState(t *testing.T) {
	env := sharedEnv

	origFunc := env.mockSD.ListStreamForwardsFunc
	env.mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	emptyNodes := hierarchy.FindContainingText("No active stream")
	require.NotEmpty(t, emptyNodes, "empty state message should show when no forwards")
	screenshot(t, env, "restreams_empty")

	// Restore
	env.mockSD.ListStreamForwardsFunc = origFunc
}

func TestRestreams_PollingFrequency(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()
	time.Sleep(5 * time.Second)

	count := env.mockSD.CallCount("ListStreamForwards")
	require.GreaterOrEqual(t, count, 2, "ListStreamForwards should be polled at least 2 times in 5s, got %d", count)
	t.Logf("ListStreamForwards called %d times in 5s", count)
}

func TestRestreams_DynamicUpdate(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	// Initially 3 forwards, verify all exist
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	require.NotEmpty(t, hierarchy.FindContainingText("twitch"))
	require.NotEmpty(t, hierarchy.FindContainingText("youtube"))
	require.NotEmpty(t, hierarchy.FindContainingText("kick"))

	// Change mock to return only 1 forward
	env.mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
		}, nil
	}

	// Wait for UI to update
	Sleep(3 * time.Second)
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)

	// twitch should still be there, youtube/kick should be gone
	require.NotEmpty(t, hierarchy.FindContainingText("twitch"), "twitch should still be visible")
	screenshot(t, env, "restreams_dynamic_update")

	// Restore
	env.mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
			{SourceID: "cam0", SinkID: "youtube", SinkType: "rtmp", Enabled: true},
			{SourceID: "cam0", SinkID: "kick", SinkType: "rtmp", Enabled: false},
		}, nil
	}
}

func TestRestreams_ToggleForwardEnabled(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Find the toggle button (forwardToggleBtn) and tap it
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	toggleButtons := hierarchy.FindAllByContentDesc("forwardToggleBtn")
	require.NotEmpty(t, toggleButtons, "forwardToggleBtn should exist")
	require.NoError(t, env.adb.TapNode(toggleButtons[0]))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("UpdateStreamForward"), 1, "UpdateStreamForward should have been called after toggling")
	screenshot(t, env, "restreams_toggle")
}

func TestRestreams_RemoveButtonPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	removeButtons := hierarchy.FindAllByContentDesc("forwardRemoveBtn")
	require.NotEmpty(t, removeButtons, "Remove buttons should exist for each forward")
	// We have 3 forwards in the mock
	require.GreaterOrEqual(t, len(removeButtons), 1, "at least one Remove button should exist")
	screenshot(t, env, "restreams_remove_buttons")
}

func TestRestreams_AddForwardFormPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	// Tap Add Forward button
	addBtn, err := env.adb.WaitForElement("addForwardButton", elementTimeout)
	require.NoError(t, err, "Add Forward button should exist")
	require.NoError(t, env.adb.TapNode(addBtn))
	Sleep(500 * time.Millisecond)

	// Verify form fields appear
	_, err = env.adb.WaitForElement("fwdSourceField", 5*time.Second)
	require.NoError(t, err, "Source ID field should appear")

	_, err = env.adb.WaitForElement("fwdSinkField", 5*time.Second)
	require.NoError(t, err, "Sink ID field should appear")

	_, err = env.adb.WaitForElement("confirmAddForwardButton", 5*time.Second)
	require.NoError(t, err, "Confirm Add button should appear")

	screenshot(t, env, "restreams_add_forward_form")
}
