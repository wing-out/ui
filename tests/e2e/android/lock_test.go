//go:build android_e2e

package android

import (
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestLock_ButtonVisible(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err, "lock button should be visible on Dashboard")
	require.NotNil(t, lockBtn)
	screenshot(t, env, "lock_button")
}

func TestLock_TapToLock(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	// Lock overlay should appear
	overlay, err := env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err, "lock overlay should appear after tapping lock")
	require.NotNil(t, overlay)

	// Verify overlay reports locked state
	require.Contains(t, overlay.ContentDesc, "locked",
		"overlay should report locked state")

	// Lock button should show filled/locked state (content-desc changes to lock_open icon)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	lockBtnNode := hierarchy.FindByContentDescPrefix("lockButton")
	require.NotNil(t, lockBtnNode, "lock button should still be in the tree")

	screenshot(t, env, "lock_tap_to_lock")
}

func TestLock_SingleTapDoesNotUnlock(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Lock the screen
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	_, err = env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err, "should be locked")

	// Single tap on the lock button area — should NOT unlock
	cx, cy, err := lockBtn.Center()
	require.NoError(t, err)
	require.NoError(t, env.adb.Tap(cx, cy))
	Sleep(500 * time.Millisecond)

	// Overlay should still be present and locked
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	overlayNode := hierarchy.FindByContentDescPrefix("lockOverlay")
	require.NotNil(t, overlayNode, "overlay should still be active after single tap")
	require.Contains(t, overlayNode.ContentDesc, "locked",
		"overlay should still report locked after single tap")

	screenshot(t, env, "lock_single_tap_stays_locked")

	// Cleanup: double-tap to unlock
	_ = env.adb.DoubleTap(cx, cy)
	Sleep(500 * time.Millisecond)
}

func TestLock_DoubleTapToUnlock(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Lock the screen
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	cx, cy, err := lockBtn.Center()
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	_, err = env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err, "should be locked")

	// Double-tap the lock button to unlock
	require.NoError(t, env.adb.DoubleTap(cx, cy))
	Sleep(500 * time.Millisecond)

	// Overlay should report unlocked or be gone
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	overlayNode := hierarchy.FindByContentDescPrefix("lockOverlay")
	if overlayNode != nil {
		require.Contains(t, overlayNode.ContentDesc, "unlocked",
			"overlay should report unlocked after double-tap")
	}

	// Dashboard should be interactable — verify menu button responds
	menuBtn, err := env.adb.WaitForElement("menuButton", elementTimeout)
	require.NoError(t, err, "menu button should be accessible after unlock")
	require.NotNil(t, menuBtn)

	screenshot(t, env, "lock_doubletap_unlocked")
}

func TestLock_OverlayBlocksTopBar(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Lock the screen
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	_, err = env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err)

	// Try to open nav menu while locked by tapping where the menu button is
	menuBtn, err := env.adb.WaitForElement("menuButton", elementTimeout)
	if err == nil && menuBtn != nil {
		_ = env.adb.TapNode(menuBtn)
		Sleep(1 * time.Second)
	}

	// Overlay should still be locked — the menu tap should have been blocked
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	overlayNode := hierarchy.FindByContentDescPrefix("lockOverlay")
	require.NotNil(t, overlayNode, "lock overlay should still be active")
	require.Contains(t, overlayNode.ContentDesc, "locked",
		"overlay should still report locked after trying to tap menu")

	// The page should still show Dashboard (not navigated away)
	pageTitle := hierarchy.FindByContentDescPrefix("pageTitle")
	require.NotNil(t, pageTitle, "page title should be visible")
	require.Contains(t, pageTitle.ContentDesc, "Dashboard",
		"should still be on Dashboard — menu tap was blocked")

	screenshot(t, env, "lock_blocks_topbar")

	// Cleanup: double-tap lock button to unlock
	cx, cy, _ := lockBtn.Center()
	_ = env.adb.DoubleTap(cx, cy)
	Sleep(500 * time.Millisecond)
}

func TestLock_DashboardVisibleWhileLocked(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Lock the screen
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	_, err = env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err)

	// Dashboard elements should still be visible in the hierarchy
	// (overlay is transparent, so the underlying UI is still rendered)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Check that dashboard tiles are still in the tree
	dashboard := hierarchy.FindByContentDescPrefix("dashboardPage")
	require.NotNil(t, dashboard, "dashboard page should be in the UI tree while locked")

	screenshot(t, env, "lock_dashboard_visible")

	// Cleanup
	cx, cy, _ := lockBtn.Center()
	_ = env.adb.DoubleTap(cx, cy)
	Sleep(500 * time.Millisecond)
}

func TestLock_DisablesDashboardElements(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Verify elements are enabled before locking
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	dashEl := hierarchy.FindByContentDescPrefix("dashboardVideoPreview")
	require.NotNil(t, dashEl)
	require.Equal(t, "true", dashEl.Enabled,
		"dashboardVideoPreview should be enabled before locking")

	// Lock the screen
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(lockBtn))
	Sleep(500 * time.Millisecond)

	_, err = env.adb.WaitForElement("lockOverlay", elementTimeout)
	require.NoError(t, err, "should be locked")

	// Dump UI and verify dashboard elements are disabled
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)

	// Top bar should be disabled
	topBar := hierarchy.FindByContentDescPrefix("topBar")
	require.NotNil(t, topBar, "topBar should be in the tree")
	require.Equal(t, "false", topBar.Enabled,
		"topBar should be disabled while locked")

	// Menu button should be disabled
	menuBtn := hierarchy.FindByContentDescPrefix("menuButton")
	require.NotNil(t, menuBtn, "menuButton should be in the tree")
	require.Equal(t, "false", menuBtn.Enabled,
		"menuButton should be disabled while locked")

	// Dashboard page should be disabled
	dashboard := hierarchy.FindByContentDescPrefix("dashboardPage")
	require.NotNil(t, dashboard, "dashboardPage should be in the tree")
	require.Equal(t, "false", dashboard.Enabled,
		"dashboardPage should be disabled while locked")

	// Dashboard elements should be disabled
	dashEl = hierarchy.FindByContentDescPrefix("dashboardVideoPreview")
	require.NotNil(t, dashEl)
	require.Equal(t, "false", dashEl.Enabled,
		"dashboardVideoPreview should be disabled while locked")

	// Lock button itself should still be enabled (above overlay)
	lockBtnNode := hierarchy.FindByContentDescPrefix("lockButton")
	require.NotNil(t, lockBtnNode)
	require.Equal(t, "true", lockBtnNode.Enabled,
		"lock button should remain enabled while locked")

	screenshot(t, env, "lock_elements_disabled")

	// Cleanup: double-tap to unlock
	cx, cy, _ := lockBtn.Center()
	_ = env.adb.DoubleTap(cx, cy)
	Sleep(500 * time.Millisecond)

	// After unlock, elements should be enabled again
	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	dashEl = hierarchy.FindByContentDescPrefix("dashboardVideoPreview")
	require.NotNil(t, dashEl)
	require.Equal(t, "true", dashEl.Enabled,
		"dashboardVideoPreview should be re-enabled after unlock")
}

func TestLock_ButtonOnlyOnDashboard(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Navigate to Cameras page using the helper
	navigateToPage(t, env, "Cameras")
	Sleep(500 * time.Millisecond)

	// Lock button should NOT be visible on non-dashboard pages
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	lockBtnNode := hierarchy.FindByContentDescPrefix("lockButton")
	if lockBtnNode != nil {
		// If found, it should not be visible (bounds should be zero-size)
		var x1, y1, x2, y2 int
		fmt.Sscanf(lockBtnNode.Bounds, "[%d,%d][%d,%d]", &x1, &y1, &x2, &y2)
		w := x2 - x1
		h := y2 - y1
		if w > 0 && h > 0 {
			t.Error("lock button should not be visible on non-dashboard pages")
		}
	}

	screenshot(t, env, "lock_not_on_cameras")
}
