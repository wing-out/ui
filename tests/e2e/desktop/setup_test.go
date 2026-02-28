//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_InitialSetupVisible(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)

	node, err := env.atspi.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err, "initial setup dialog should appear on fresh launch")
	require.NotNil(t, node)
	screenshot(t, env, "setup_visible")
}

func TestDesktop_ConnectToServer(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)

	_, err := env.atspi.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	// Type server address into host field
	require.NoError(t, env.atspi.ActivateByName("hostField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText(env.srvAddr))
	Sleep(300 * time.Millisecond)

	// Click Connect
	require.NoError(t, env.atspi.ActivateByName("connectButton"))
	Sleep(2 * time.Second)

	// Setup should disappear, dashboard should be visible
	dashboard, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard should be visible after setup")
	require.NotNil(t, dashboard)

	// Initial setup should be gone
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	setupNode := tree.FindByName("initialSetup")
	require.Nil(t, setupNode, "initial setup should not be visible after connecting")
	screenshot(t, env, "after_connect")
}

func TestDesktop_SetupPersists(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Verify dashboard is visible
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
	require.NotNil(t, dashboard, "dashboard should be visible after restart")
	screenshot(t, env, "setup_persists")
}

func TestDesktop_ModeSelection(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)

	_, err := env.atspi.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	modes := []string{"Remote", "Embedded", "Hybrid"}
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			tree, err := env.atspi.DumpTree()
			require.NoError(t, err)
			modeNodes := tree.FindContainingText(mode)
			require.NotEmpty(t, modeNodes, "mode button %q should exist", mode)
			_ = env.atspi.ActivateByName(mode)
			Sleep(300 * time.Millisecond)
			screenshot(t, env, "mode_"+mode)
		})
	}
}

func TestDesktop_EmbeddedDefaultsHost(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)

	_, err := env.atspi.WaitForElement("initialSetup", elementTimeout)
	require.NoError(t, err)

	// Select Embedded mode
	_ = env.atspi.ActivateByName("Embedded")
	Sleep(500 * time.Millisecond)

	// Connect without entering a host
	require.NoError(t, env.atspi.ActivateByName("connectButton"))
	Sleep(2 * time.Second)

	// Navigate to Settings and check for default host
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	nodes := tree.FindContainingText("127.0.0.1")
	require.NotEmpty(t, nodes, "embedded mode should default host to 127.0.0.1")
	screenshot(t, env, "embedded_default_host")
}
