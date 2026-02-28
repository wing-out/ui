//go:build android_e2e

package android

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestSetup_DialogVisibleOnFreshInstall(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	node, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err, "initial setup dialog should appear on fresh install")
	require.NotNil(t, node)
	screenshot(t, env, "setup_visible")
}

func TestSetup_ConnectDisabledWithEmptyHost(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	// In Remote mode with empty host, connect should be disabled
	connectBtn, err := env.adb.WaitForElement("connectButton", elementTimeout)
	require.NoError(t, err)
	require.Equal(t, "false", connectBtn.Enabled, "connect button should be disabled with empty host in Remote mode")
	screenshot(t, env, "connect_disabled")
}

func TestSetup_ConnectEnabledWithHost(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	hostField, err := env.adb.WaitForElement("hostField", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(hostField))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.adb.TypeText(env.srvAddr))
	Sleep(500 * time.Millisecond)

	connectBtn, err := env.adb.WaitForElement("connectButton", elementTimeout)
	require.NoError(t, err)
	require.Equal(t, "true", connectBtn.Enabled, "connect button should be enabled after typing host")
	screenshot(t, env, "connect_enabled")
}

func TestSetup_ConnectEnabledInEmbeddedNoHost(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	// Tap Embedded mode (button accessible name = "Embedded")
	embeddedBtn, err := env.adb.WaitForElement("Embedded", elementTimeout)
	require.NoError(t, err, "Embedded mode button should exist")
	require.NoError(t, env.adb.TapNode(embeddedBtn))
	Sleep(500 * time.Millisecond)

	// Connect should be enabled without host
	connectBtn, err := env.adb.WaitForElement("connectButton", elementTimeout)
	require.NoError(t, err)
	require.Equal(t, "true", connectBtn.Enabled, "connect should be enabled in Embedded mode without host")
	screenshot(t, env, "embedded_no_host")
}

func TestSetup_ModeSelection(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	modes := []string{"Remote", "Embedded", "Hybrid"}
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			// Mode buttons use Accessible.name = text (e.g. "Remote")
			modeBtn, err := env.adb.WaitForElement(mode, elementTimeout)
			require.NoError(t, err, "mode button %q should exist", mode)
			require.NoError(t, env.adb.TapNode(modeBtn))
			Sleep(300 * time.Millisecond)
			screenshot(t, env, "mode_"+mode)
		})
	}
}

func TestSetup_ConnectNavigatesToDashboard(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

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

	// Setup should disappear, dashboard should be visible
	dashboard, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard should be visible after setup")
	require.NotNil(t, dashboard)

	// Initial setup should be gone
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	setupNode := hierarchy.FindByContentDesc("initialSetup")
	require.Nil(t, setupNode, "initial setup should not be visible after connecting")
	screenshot(t, env, "after_connect")
}

func TestSetup_EmbeddedDefaultsHost(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)

	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	// Select Embedded mode (button accessible name = "Embedded")
	embeddedBtn, err := env.adb.WaitForElement("Embedded", elementTimeout)
	require.NoError(t, err, "Embedded mode button should exist")
	require.NoError(t, env.adb.TapNode(embeddedBtn))
	Sleep(500 * time.Millisecond)

	// Connect without entering a host
	connectBtn, err := env.adb.WaitForElement("connectButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(connectBtn))
	Sleep(2 * time.Second)

	// Navigate to Settings and check the host field
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	nodes := hierarchy.FindContainingText("127.0.0.1")
	require.NotEmpty(t, nodes, "embedded mode should default host to 127.0.0.1")
	screenshot(t, env, "embedded_default_host")
}
