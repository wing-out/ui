//go:build android_e2e

package android

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestFlow_CompleteWalkthrough(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	// Step 1: Fresh install — setup dialog should appear
	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err, "setup should appear on fresh install")
	screenshot(t, env, "flow_01_setup")

	// Step 2: Enter server address and connect
	hostField, err := env.adb.WaitForElement("hostField", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(hostField))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.adb.TypeText(env.srvAddr))
	Sleep(300 * time.Millisecond)
	// Dismiss keyboard so connect button is tappable
	require.NoError(t, env.adb.PressBack())
	Sleep(500 * time.Millisecond)

	connectBtn, err := env.adb.WaitForElement("connectButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(connectBtn))
	Sleep(2 * time.Second)
	screenshot(t, env, "flow_02_dashboard")

	// Step 3: Verify new Dashboard has video preview and chat
	_, err = env.adb.WaitForElement("dashboardVideoPreview", elementTimeout)
	require.NoError(t, err, "dashboard video preview should load")

	// Step 4: Navigate to Status page and verify metrics
	navigateToPage(t, env, "Status")
	waitForMetricValue(t, env, "inputBitrateTile", "6.0", 5*time.Second)
	screenshot(t, env, "flow_03_metrics")

	// Step 5: Navigate through all pages
	allPages := []string{"Cameras", "DJI Control", "Chat", "Players", "Restreams", "Monitor", "Profiles", "Logs", "Settings"}
	for i, page := range allPages {
		navigateToPage(t, env, page)
		screenshot(t, env, fmt.Sprintf("flow_%02d_%s", i+4, page))
	}

	// Step 6: Verify data on Profiles page
	navigateToPage(t, env, "Profiles")
	Sleep(1 * time.Second)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	require.NotEmpty(t, hierarchy.FindContainingText("IRL 720p"), "profile data should be present")

	// Step 7: Verify data on Restreams page
	navigateToPage(t, env, "Restreams")
	Sleep(1 * time.Second)
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	require.NotEmpty(t, hierarchy.FindContainingText("twitch"), "restream data should be present")

	// Step 8: Go back to Dashboard
	navigateToPage(t, env, "Dashboard")
	Sleep(1 * time.Second)
	screenshot(t, env, "flow_back_to_dashboard")

	// Step 9: Lock and unlock
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "flow_locked")

	overlay, err := env.adb.WaitForElement("lockOverlay", 5*time.Second)
	require.NoError(t, err)
	cx, cy, err := overlay.Center()
	require.NoError(t, err)
	require.NoError(t, env.adb.DoubleTap(cx, cy))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "flow_unlocked")

	// Step 10: Dynamic mock update — navigate to Status to check metric tiles
	navigateToPage(t, env, "Status")
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 3000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 2000000, Audio: 128000},
		}, nil
	}
	waitForMetricValue(t, env, "inputBitrateTile", "3.0", 5*time.Second)
	screenshot(t, env, "flow_dynamic_update")

	// Restore mock
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 6000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 4500000, Audio: 128000},
		}, nil
	}

	// Step 11: Background/foreground
	require.NoError(t, env.adb.PressHome())
	Sleep(2 * time.Second)
	require.NoError(t, env.adb.LaunchApp())
	Sleep(2 * time.Second)

	node, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard should be visible after foreground")
	require.NotNil(t, node)
	screenshot(t, env, "flow_after_foreground")

	// Step 12: Verify backend call counts
	env.mockFF.ResetCallCounts()
	env.mockSD.ResetCallCounts()
	Sleep(2 * time.Second)
	require.Greater(t, env.mockFF.CallCount("GetBitRates"), 0, "backend should be actively polled")

	// Step 13: Verify connection status badges (SD / FF)
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	sdBadge := hierarchy.FindByContentDesc("streamdStatus")
	ffBadge := hierarchy.FindByContentDesc("ffstreamStatus")
	require.True(t, sdBadge != nil || ffBadge != nil, "connection status badges should be visible")
	screenshot(t, env, "flow_complete")

	t.Log("Full walkthrough complete: 13 steps verified")
}
