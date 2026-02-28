//go:build android_e2e

package android

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestLifecycle_BackgroundForeground(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Verify dashboard is visible
	_, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	// Send to background
	require.NoError(t, env.adb.PressHome())
	Sleep(2 * time.Second)

	// Bring back to foreground
	require.NoError(t, env.adb.LaunchApp())
	Sleep(2 * time.Second)

	// Dashboard should still be visible
	node, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard should be visible after foreground")
	require.NotNil(t, node)
	screenshot(t, env, "after_foreground")
}

func TestLifecycle_Rotation(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Disable auto-rotation and set to landscape
	env.adb.Shell("settings", "put", "system", "accelerometer_rotation", "0")
	env.adb.Shell("settings", "put", "system", "user_rotation", "1") // landscape
	Sleep(2 * time.Second)
	screenshot(t, env, "landscape")

	// Rotate back to portrait
	env.adb.Shell("settings", "put", "system", "user_rotation", "0") // portrait
	Sleep(2 * time.Second)

	// App should still function
	node, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard should be visible after rotation")
	require.NotNil(t, node)

	// Restore auto-rotation
	env.adb.Shell("settings", "put", "system", "accelerometer_rotation", "1")
	screenshot(t, env, "portrait_after_rotation")
}

func TestLifecycle_SettingsPersistOnRestart(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Verify we're on the dashboard
	_, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	// Force-stop and relaunch (without clearing data)
	require.NoError(t, env.adb.StopApp())
	Sleep(1 * time.Second)
	require.NoError(t, env.adb.LaunchApp())
	Sleep(3 * time.Second)

	// Setup should NOT appear again (settings persisted)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	setupNode := hierarchy.FindByContentDesc("initialSetup")
	require.Nil(t, setupNode, "initial setup should NOT appear after restart with persisted settings")

	// Dashboard should be directly visible
	dashboard := hierarchy.FindByContentDesc("dashboardPage")
	require.NotNil(t, dashboard, "dashboard should be directly visible after restart")
	screenshot(t, env, "persists_on_restart")
}
