//go:build android_e2e

package android

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// freshApp clears app data and relaunches for a clean state.
func freshApp(t *testing.T, env *testEnv) {
	t.Helper()
	require.NoError(t, env.adb.ClearAppData(), "clear data")
	require.NoError(t, env.adb.LaunchApp(), "launch app")
	Sleep(3 * time.Second)
}

// completeSetup types the server address and taps Connect to get past the initial setup dialog.
func completeSetup(t *testing.T, env *testEnv) {
	t.Helper()
	_, err := env.adb.WaitForElement("initialSetup", elementTimeout)
	if err != nil {
		return // already past setup
	}
	hostField, err := env.adb.WaitForElement("hostField", 5*time.Second)
	if err != nil {
		return
	}
	require.NoError(t, env.adb.TapNode(hostField))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.adb.TypeText(env.srvAddr))
	Sleep(300 * time.Millisecond)
	// Dismiss keyboard so connect button is tappable
	require.NoError(t, env.adb.PressBack())
	Sleep(500 * time.Millisecond)
	connectBtn, err := env.adb.WaitForElement("connectButton", 5*time.Second)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(connectBtn))
	Sleep(2 * time.Second)
}

// openNavMenu taps the hamburger menu button.
func openNavMenu(t *testing.T, env *testEnv) {
	t.Helper()
	menuBtn, err := env.adb.WaitForElement("menuButton", elementTimeout)
	require.NoError(t, err, "menu button should be visible")
	require.NoError(t, env.adb.TapNode(menuBtn))
	Sleep(500 * time.Millisecond)
}

// navigateToPage opens the nav menu and taps the given page name.
func navigateToPage(t *testing.T, env *testEnv, pageName string) {
	t.Helper()
	openNavMenu(t, env)
	// Nav menu items have Accessible.name = label (e.g. "Dashboard", "Settings")
	pageNode, err := env.adb.WaitForElement(pageName, elementTimeout)
	require.NoError(t, err, "nav menu item %q should exist", pageName)
	require.NoError(t, env.adb.TapNode(pageNode))
	Sleep(1 * time.Second)
}

// resetApp clears data and relaunches for a fresh state.
func resetApp(t *testing.T, env *testEnv) {
	t.Helper()
	require.NoError(t, env.adb.StopApp())
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.ClearAppData())
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.LaunchApp())
	Sleep(3 * time.Second)
}

// getMetricTileValue finds a tile by accessible name and extracts its value.
// On Android Qt, the tile value is embedded in content-desc as "tileName, value".
func getMetricTileValue(t *testing.T, env *testEnv, tileAccessibleName string) []string {
	t.Helper()
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	tile := hierarchy.FindByContentDesc(tileAccessibleName)
	if tile == nil {
		return nil
	}
	// On Android Qt, text attributes are empty. The value is in the content-desc
	// as "tileName, value" (Qt concatenates Accessible.name and Accessible.description).
	if strings.HasPrefix(tile.ContentDesc, tileAccessibleName+", ") {
		val := strings.TrimPrefix(tile.ContentDesc, tileAccessibleName+", ")
		return []string{val}
	}
	// Fallback: try child texts (works on desktop)
	return tile.GetChildTexts()
}

// waitForMetricValue polls until a tile's child texts contain the expected substring.
func waitForMetricValue(t *testing.T, env *testEnv, tile, expected string, timeout time.Duration) {
	t.Helper()
	err := env.adb.WaitForCondition(
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

// scrollToElement scrolls down until the element has valid (non-zero) bounds.
// Qt on Android reports [0,0][0,0] bounds for off-screen Flickable children.
// The swipe is performed at y=600→100 (in the gap area above config editors)
// to avoid activating interactive elements like TextArea/ScrollView.
func scrollToElement(t *testing.T, env *testEnv, contentDesc string) *UINode {
	t.Helper()
	for i := 0; i < 10; i++ {
		hierarchy, err := env.adb.DumpUI()
		if err != nil {
			Sleep(500 * time.Millisecond)
			continue
		}
		node := hierarchy.FindByContentDesc(contentDesc)
		if node == nil {
			// Also check prefix match
			node = hierarchy.FindByContentDescPrefix(contentDesc + ",")
		}
		if node != nil && node.Bounds != "[0,0][0,0]" && node.Bounds != "" {
			return node
		}
		// Scroll down using a swipe in the upper part of the screen
		// to avoid landing on interactive elements (TextArea, SearchField)
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(500 * time.Millisecond)
	}
	t.Fatalf("element %q not found with valid bounds after scrolling", contentDesc)
	return nil
}

// screenshot captures a screenshot to the artifacts directory.
func screenshot(t *testing.T, env *testEnv, name string) {
	t.Helper()
	path := fmt.Sprintf("%s/%s_%s.png", screenshotDir, t.Name(), name)
	if err := env.adb.Screenshot(path); err != nil {
		t.Logf("screenshot failed: %v", err)
	} else {
		t.Logf("screenshot saved: %s", path)
	}
}
