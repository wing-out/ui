//go:build desktop_e2e

package desktop

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDesktop_ProfilesList(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	profiles720 := tree.FindContainingText("IRL 720p")
	require.NotEmpty(t, profiles720, "IRL 720p profile should be visible")

	profiles1080 := tree.FindContainingText("Home 1080p")
	require.NotEmpty(t, profiles1080, "Home 1080p profile should be visible")

	// Check descriptions
	desc720 := tree.FindContainingText("720p outdoor")
	require.NotEmpty(t, desc720, "720p profile description should be visible")

	desc1080 := tree.FindContainingText("1080p home studio")
	require.NotEmpty(t, desc1080, "1080p profile description should be visible")
	screenshot(t, env, "profiles_data")
}

func TestDesktop_StartStopButtons(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	startButtons := tree.FindContainingText("Start")
	require.NotEmpty(t, startButtons, "Start buttons should be present on profile cards")
	screenshot(t, env, "profiles_start_buttons")
}

func TestDesktop_ProfilesEmptyState(t *testing.T) {
	env := sharedEnv

	// Override mock to return empty list
	origFunc := env.mockSD.ListProfilesFunc
	env.mockSD.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{}, nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	emptyNodes := tree.FindContainingText("No profiles")
	require.NotEmpty(t, emptyNodes, "empty state message should be visible")
	screenshot(t, env, "profiles_empty")

	// Restore
	env.mockSD.ListProfilesFunc = origFunc
}

func TestDesktop_ProfilesBackendCalled(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	env.mockSD.ResetCallCounts()
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ListProfiles"), 1, "ListProfiles should have been called")
}

func TestDesktop_ProfileStartStopButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	btn := tree.FindByName("profileStartStopBtn")
	require.NotNil(t, btn, "profile start/stop button should exist")
	screenshot(t, env, "profiles_start_stop_button")
}

func TestDesktop_ProfileApplyButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	btn := tree.FindByName("profileApplyBtn")
	require.NotNil(t, btn, "profile apply button should exist")
	screenshot(t, env, "profiles_apply_button")
}

func TestDesktop_ProfileEditButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	btn := tree.FindByName("profileEditBtn")
	require.NotNil(t, btn, "profile edit button should exist")
	screenshot(t, env, "profiles_edit_button")
}

func TestDesktop_ProfileStartStopCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Tap start/stop button
	require.NoError(t, env.atspi.ActivateByName("profileStartStopBtn"))
	Sleep(1 * time.Second)

	startCount := env.mockSD.CallCount("StartStream")
	endCount := env.mockSD.CallCount("EndStream")
	require.GreaterOrEqual(t, startCount+endCount, 1,
		"StartStream or EndStream should have been called, got start=%d end=%d", startCount, endCount)
	screenshot(t, env, "profiles_start_stop_backend")
}

func TestDesktop_ProfileApplyCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Tap apply button
	require.NoError(t, env.atspi.ActivateByName("profileApplyBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ApplyProfile"), 1,
		"ApplyProfile should have been called")
	screenshot(t, env, "profiles_apply_backend")
}

func TestDesktop_ProfilesPageTitle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Profiles"), "'Profiles' title should be visible")
	screenshot(t, env, "profiles_title")
}

func TestDesktop_ProfilesPollingFrequency(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()
	time.Sleep(5 * time.Second)

	count := env.mockSD.CallCount("ListProfiles")
	require.GreaterOrEqual(t, count, 2, "ListProfiles should be polled at least 2 times in 5s, got %d", count)
	t.Logf("ListProfiles called %d times in 5s", count)
}
