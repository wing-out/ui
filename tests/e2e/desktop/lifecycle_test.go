//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_AppRestart(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Verify dashboard is visible
	_, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	// Navigate to Chat to change state
	navigateToPage(t, env, "Chat")
	_, err = env.atspi.WaitForElement("chatPage", elementTimeout)
	require.NoError(t, err)

	// Stop and relaunch
	stopApp(t, env)
	Sleep(1 * time.Second)
	launchApp(t, env)
	Sleep(3 * time.Second)

	// After restart, the app should come back up (setup should not appear if persisted)
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	require.NotNil(t, tree, "app should restart successfully")

	// The app should have a top bar
	topBar := tree.FindByName("topBar")
	require.NotNil(t, topBar, "top bar should be visible after restart")
	screenshot(t, env, "after_restart")
}

func TestDesktop_SettingsPersistence(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Verify we're on the dashboard
	_, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	// Stop and relaunch (without clearing data)
	stopApp(t, env)
	Sleep(1 * time.Second)
	launchApp(t, env)
	Sleep(3 * time.Second)

	// Setup should NOT appear again (settings persisted)
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	setupNode := tree.FindByName("initialSetup")
	require.Nil(t, setupNode, "initial setup should NOT appear after restart with persisted settings")

	// Dashboard should be directly visible
	dashboard := tree.FindByName("dashboardPage")
	require.NotNil(t, dashboard, "dashboard should be directly visible after restart")
	screenshot(t, env, "settings_persist")
}

func TestDesktop_HostPersistsAcrossRestart(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Stop and relaunch (without clearing data)
	stopApp(t, env)
	Sleep(1 * time.Second)
	launchApp(t, env)
	Sleep(3 * time.Second)

	// Navigate to Settings
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	// The host should still be set
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	hostNodes := tree.FindContainingText("127.0.0.1")
	if len(hostNodes) == 0 {
		// May show the actual server address instead
		hostNodes = tree.FindContainingText(env.srvAddr)
	}
	require.NotEmpty(t, hostNodes, "host should persist across restart")
	screenshot(t, env, "host_persists")
}

func TestDesktop_ConnectionStatusBadge(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	connNodes := tree.FindContainingText("Connected")
	if len(connNodes) == 0 {
		connNodes = tree.FindContainingText("Disconnected")
	}
	require.NotEmpty(t, connNodes, "connection status should be visible")
	screenshot(t, env, "connection_status")
}

func TestDesktop_BackendCallFrequency(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	// Reset call counts and wait
	env.mockFF.ResetCallCounts()
	time.Sleep(2 * time.Second)

	// The dashboard polls periodically; we expect several calls
	callCount := env.mockFF.CallCount("GetBitRates")
	require.Greater(t, callCount, 5, "GetBitRates should have been called >5 times in 2s, got %d", callCount)
	t.Logf("GetBitRates called %d times in 2s", callCount)
}

func TestDesktop_WindowResizeDoesNotCrash(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	_, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	// Resize the window using xdotool
	require.NoError(t, env.atspi.PressKey("super+Up"))
	Sleep(1 * time.Second)

	// App should still function
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	require.NotNil(t, tree, "app should survive window resize")

	// Restore window
	require.NoError(t, env.atspi.PressKey("super+Down"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "after_resize")
}
