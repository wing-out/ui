//go:build desktop_e2e

package desktop

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// launchApp starts the wingout binary and waits for it to become visible via AT-SPI2.
func launchApp(t *testing.T, env *testEnv) {
	t.Helper()
	binaryPath := os.Getenv("WINGOUT_BINARY_PATH")
	require.NotEmpty(t, binaryPath, "WINGOUT_BINARY_PATH must be set")

	cmd := exec.Command(binaryPath)
	cmd.Env = append(os.Environ(),
		"QT_ACCESSIBILITY=1",
		fmt.Sprintf("WINGOUT_SERVER_ADDR=%s", env.srvAddr),
	)
	require.NoError(t, cmd.Start(), "start wingout binary")

	env.appCmd = cmd
	env.appPID = cmd.Process.Pid
	env.atspi.SetPID(env.appPID)

	// Wait for the app to appear in the AT-SPI2 tree
	deadline := time.Now().Add(appStartTimeout)
	for time.Now().Before(deadline) {
		tree, err := env.atspi.DumpTree()
		if err == nil && tree != nil && tree.Name != "" {
			return
		}
		time.Sleep(1 * time.Second)
	}
	t.Log("warning: app may not have appeared in AT-SPI2 tree within timeout")
}

// stopApp kills the running application process.
func stopApp(t *testing.T, env *testEnv) {
	t.Helper()
	if env.appCmd != nil && env.appCmd.Process != nil {
		_ = env.appCmd.Process.Kill()
		_ = env.appCmd.Wait()
		env.appCmd = nil
		env.appPID = 0
	}
}

// freshApp stops any running instance, then launches a fresh one.
func freshApp(t *testing.T, env *testEnv) {
	t.Helper()
	stopApp(t, env)
	Sleep(500 * time.Millisecond)
	launchApp(t, env)
	Sleep(3 * time.Second)
}

// completeSetup fills in the server address via AT-SPI2 and clicks Connect
// to get past the initial setup dialog.
func completeSetup(t *testing.T, env *testEnv) {
	t.Helper()
	_, err := env.atspi.WaitForElement("initialSetup", elementTimeout)
	if err != nil {
		return // already past setup
	}

	// Activate the host field and type the server address
	err = env.atspi.ActivateByName("hostField")
	if err != nil {
		return
	}
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText(env.srvAddr))
	Sleep(300 * time.Millisecond)

	// Click Connect
	require.NoError(t, env.atspi.ActivateByName("connectButton"))
	Sleep(2 * time.Second)
}

// openNavMenu activates the hamburger menu button.
func openNavMenu(t *testing.T, env *testEnv) {
	t.Helper()
	require.NoError(t, env.atspi.ActivateByName("menuButton"), "open nav menu")
	Sleep(500 * time.Millisecond)
}

// navigateToPage opens the nav menu and clicks the given page name.
func navigateToPage(t *testing.T, env *testEnv, pageName string) {
	t.Helper()
	openNavMenu(t, env)
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	pageNodes := tree.FindContainingText(pageName)
	require.NotEmpty(t, pageNodes, "nav menu item %q should exist", pageName)
	require.NoError(t, env.atspi.ActivateByName(pageName))
	Sleep(1 * time.Second)
}

// screenshot captures a screenshot to the artifacts directory.
func screenshot(t *testing.T, env *testEnv, name string) {
	t.Helper()
	safeName := strings.ReplaceAll(t.Name(), "/", "_")
	path := filepath.Join(screenshotDir, fmt.Sprintf("%s_%s.png", safeName, name))
	if err := env.atspi.Screenshot(path); err != nil {
		t.Logf("screenshot failed: %v", err)
	} else {
		t.Logf("screenshot saved: %s", path)
	}
}

// getMetricTileValue finds a tile by accessible name and extracts child text values.
func getMetricTileValue(t *testing.T, env *testEnv, tileAccessibleName string) []string {
	t.Helper()
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	tile := tree.FindByName(tileAccessibleName)
	if tile == nil {
		tile = tree.FindByDescription(tileAccessibleName)
	}
	if tile == nil {
		return nil
	}
	// Collect the tile's description (which is the value) and child texts
	var texts []string
	if tile.Description != "" {
		texts = append(texts, tile.Description)
	}
	texts = append(texts, tile.GetChildTexts()...)
	return texts
}

// waitForMetricValue polls until a tile's text content contains the expected substring.
func waitForMetricValue(t *testing.T, env *testEnv, tile, expected string, timeout time.Duration) {
	t.Helper()
	err := env.atspi.WaitForCondition(
		fmt.Sprintf("tile %q contains %q", tile, expected),
		timeout,
		func() bool {
			texts := getMetricTileValue(t, env, tile)
			joined := strings.Join(texts, " ")
			return strings.Contains(joined, expected)
		},
	)
	require.NoError(t, err)
}
