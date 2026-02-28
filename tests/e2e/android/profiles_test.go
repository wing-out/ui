//go:build android_e2e

package android

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestProfiles_ShowsMockData(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	profiles720 := hierarchy.FindContainingText("IRL 720p")
	require.NotEmpty(t, profiles720, "IRL 720p profile should be visible")

	profiles1080 := hierarchy.FindContainingText("Home 1080p")
	require.NotEmpty(t, profiles1080, "Home 1080p profile should be visible")

	// Check descriptions
	desc720 := hierarchy.FindContainingText("720p outdoor")
	require.NotEmpty(t, desc720, "720p profile description should be visible")

	desc1080 := hierarchy.FindContainingText("1080p home studio")
	require.NotEmpty(t, desc1080, "1080p profile description should be visible")

	screenshot(t, env, "profiles_data")
}

func TestProfiles_EmptyState(t *testing.T) {
	env := sharedEnv

	// Override mock to return empty list
	origFunc := env.mockSD.ListProfilesFunc
	env.mockSD.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	emptyNodes := hierarchy.FindContainingText("No profiles")
	require.NotEmpty(t, emptyNodes, "empty state message should be visible")
	screenshot(t, env, "profiles_empty")

	// Restore
	env.mockSD.ListProfilesFunc = origFunc
}

func TestProfiles_StartButtonsPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	startButtons := hierarchy.FindContainingText("Start")
	require.NotEmpty(t, startButtons, "Start buttons should be present on profile cards")
	screenshot(t, env, "profiles_start_buttons")
}

func TestProfiles_BackendCalled(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	env.mockSD.ResetCallCounts()
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ListProfiles"), 1, "ListProfiles should have been called")
}

func TestProfiles_StartStreamCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Find the first Start button (profileStartStopBtn shows "Start" when no active profile)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	startButtons := hierarchy.FindAllByContentDesc("profileStartStopBtn")
	require.NotEmpty(t, startButtons, "profileStartStopBtn should exist")
	require.NoError(t, env.adb.TapNode(startButtons[0]))
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("StartStream"), 1, "StartStream should have been called after tapping Start")
	screenshot(t, env, "profiles_start_stream")
}

func TestProfiles_StopStreamCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	// First tap Start to make a profile active
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	startButtons := hierarchy.FindAllByContentDesc("profileStartStopBtn")
	require.NotEmpty(t, startButtons, "profileStartStopBtn should exist")
	require.NoError(t, env.adb.TapNode(startButtons[0]))
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Now the button should show "Stop", tap it again
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	stopButtons := hierarchy.FindAllByContentDesc("profileStartStopBtn")
	require.NotEmpty(t, stopButtons, "profileStartStopBtn should still exist")
	require.NoError(t, env.adb.TapNode(stopButtons[0]))
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("EndStream"), 1, "EndStream should have been called after tapping Stop")
	screenshot(t, env, "profiles_stop_stream")
}

func TestProfiles_ApplyProfileCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Profiles")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Find the Apply button
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	applyButtons := hierarchy.FindAllByContentDesc("profileApplyBtn")
	require.NotEmpty(t, applyButtons, "profileApplyBtn should exist")
	require.NoError(t, env.adb.TapNode(applyButtons[0]))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ApplyProfile"), 1, "ApplyProfile should have been called after tapping Apply")
	screenshot(t, env, "profiles_apply")
}
