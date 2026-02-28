//go:build desktop_e2e

package desktop

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDesktop_ForwardsList(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("twitch"), "twitch forward should be visible")
	require.NotEmpty(t, tree.FindContainingText("youtube"), "youtube forward should be visible")
	require.NotEmpty(t, tree.FindContainingText("kick"), "kick forward should be visible")
	require.NotEmpty(t, tree.FindContainingText("cam0"), "source cam0 should be visible")
	screenshot(t, env, "restreams_list")
}

func TestDesktop_ActiveDisabledBadges(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	activeNodes := tree.FindContainingText("Active")
	require.NotEmpty(t, activeNodes, "Active badge should exist for enabled forwards")

	disabledNodes := tree.FindContainingText("Disabled")
	require.NotEmpty(t, disabledNodes, "Disabled badge should exist for kick (enabled=false)")
	screenshot(t, env, "restreams_badges")
}

func TestDesktop_RestreamsEmptyState(t *testing.T) {
	env := sharedEnv

	origFunc := env.mockSD.ListStreamForwardsFunc
	env.mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{}, nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	emptyNodes := tree.FindContainingText("No active stream")
	require.NotEmpty(t, emptyNodes, "empty state message should show when no forwards")
	screenshot(t, env, "restreams_empty")

	// Restore
	env.mockSD.ListStreamForwardsFunc = origFunc
}

func TestDesktop_RestreamsDynamicUpdate(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	// Initially 3 forwards
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	require.NotEmpty(t, tree.FindContainingText("twitch"))
	require.NotEmpty(t, tree.FindContainingText("youtube"))
	require.NotEmpty(t, tree.FindContainingText("kick"))

	// Change mock to return only 1 forward
	env.mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
		}, nil
	}

	Sleep(3 * time.Second)
	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("twitch"), "twitch should still be visible")
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

func TestDesktop_RestreamsPollingFrequency(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()
	time.Sleep(5 * time.Second)

	count := env.mockSD.CallCount("ListStreamForwards")
	require.GreaterOrEqual(t, count, 2, "ListStreamForwards should be polled at least 2 times in 5s, got %d", count)
	t.Logf("ListStreamForwards called %d times in 5s", count)
}

func TestDesktop_ForwardToggleButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	toggleBtn := tree.FindByName("forwardToggleBtn")
	require.NotNil(t, toggleBtn, "forward toggle button should exist")
	screenshot(t, env, "restreams_toggle_button")
}

func TestDesktop_ForwardToggleCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Tap toggle button
	require.NoError(t, env.atspi.ActivateByName("forwardToggleBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("UpdateStreamForward"), 1,
		"UpdateStreamForward should have been called after toggling")
	screenshot(t, env, "restreams_toggle_backend")
}

func TestDesktop_ForwardRemoveButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	removeBtn := tree.FindByName("forwardRemoveBtn")
	require.NotNil(t, removeBtn, "forward remove button should exist")
	screenshot(t, env, "restreams_remove_button")
}

func TestDesktop_AddForwardButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	addBtn := tree.FindByName("addForwardButton")
	require.NotNil(t, addBtn, "Add Forward button should exist")
	screenshot(t, env, "restreams_add_button")
}

func TestDesktop_AddForwardForm(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	// Tap add forward button to open form
	require.NoError(t, env.atspi.ActivateByName("addForwardButton"))
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	sourceField := tree.FindByName("fwdSourceField")
	require.NotNil(t, sourceField, "Forward source field should exist in add form")

	sinkField := tree.FindByName("fwdSinkField")
	require.NotNil(t, sinkField, "Forward sink field should exist in add form")

	confirmBtn := tree.FindByName("confirmAddForwardButton")
	require.NotNil(t, confirmBtn, "Confirm Add Forward button should exist")
	screenshot(t, env, "restreams_add_form")
}

func TestDesktop_AddForwardCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	// Open add form
	require.NoError(t, env.atspi.ActivateByName("addForwardButton"))
	Sleep(1 * time.Second)

	// Fill source field
	require.NoError(t, env.atspi.ActivateByName("fwdSourceField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("cam0"))
	Sleep(300 * time.Millisecond)

	// Fill sink field
	require.NoError(t, env.atspi.ActivateByName("fwdSinkField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("newSink"))
	Sleep(300 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap confirm
	require.NoError(t, env.atspi.ActivateByName("confirmAddForwardButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("AddStreamForward"), 1,
		"AddStreamForward should have been called after confirming add")
	screenshot(t, env, "restreams_add_forward_backend")
}

func TestDesktop_RestreamsPageTitle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Restreams"), "'Restreams' title should be visible")
	screenshot(t, env, "restreams_title")
}
