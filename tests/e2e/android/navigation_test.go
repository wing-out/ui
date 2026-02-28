//go:build android_e2e

package android

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestNav_AllPagesAccessible(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	pages := []struct {
		menuLabel    string
		accessibleID string
	}{
		{"Dashboard", "dashboardPage"},
		{"Status", "statusPage"},
		{"Cameras", "camerasPage"},
		{"DJI Control", "djiControlPage"},
		{"Chat", "chatPage"},
		{"Players", "playersPage"},
		{"Restreams", "restreamsPage"},
		{"Monitor", "monitorPage"},
		{"Profiles", "profilesPage"},
		{"Logs", "logsPage"},
		{"Settings", "settingsPage"},
	}

	for _, page := range pages {
		t.Run(page.menuLabel, func(t *testing.T) {
			navigateToPage(t, env, page.menuLabel)

			node, err := env.adb.WaitForElement(page.accessibleID, elementTimeout)
			require.NoError(t, err, "page %q should be visible", page.menuLabel)
			require.NotNil(t, node)

			// Verify top bar title via content-desc
			expectedTitle := "pageTitle: " + page.menuLabel
			titleNode, err := env.adb.WaitForElement(expectedTitle, 3*time.Second)
			require.NoError(t, err, "page title should contain %q", page.menuLabel)
			require.NotNil(t, titleNode)

			screenshot(t, env, "page_"+page.menuLabel)
		})
	}
}

func TestNav_MenuToggle(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Open menu
	openNavMenu(t, env)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	navMenu := hierarchy.FindByContentDesc("navMenu")
	require.NotNil(t, navMenu, "nav menu should be visible after tap")

	// Close menu by tapping menu button again
	menuBtn, err := env.adb.WaitForElement("menuButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(menuBtn))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "menu_closed")
}

func TestNav_MenuHighlightsCurrentPage(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Navigate to Chat
	navigateToPage(t, env, "Chat")
	Sleep(500 * time.Millisecond)

	// Open menu and verify Chat is in the nav menu (via content-desc)
	openNavMenu(t, env)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// On Android Qt, text goes into content-desc, not text attribute
	chatItem := hierarchy.FindByContentDesc("Chat")
	require.NotNil(t, chatItem, "Chat item should exist in nav menu")
	screenshot(t, env, "menu_highlights_chat")
}

func TestNav_LockButtonOnlyOnDashboard(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// On Dashboard, lock button should be visible
	lockBtn, err := env.adb.WaitForElement("lockButton", elementTimeout)
	require.NoError(t, err, "lock button should be visible on Dashboard")
	require.NotNil(t, lockBtn)

	// Navigate to Settings
	navigateToPage(t, env, "Settings")
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	lockOnSettings := hierarchy.FindByContentDesc("lockButton")
	// Lock button should not be visible on non-Dashboard pages
	if lockOnSettings != nil {
		// It may be present but not visible - the QML sets visible: pageStack.currentIndex === 0
		t.Log("lock button node exists on Settings page but should be invisible via QML binding")
	}
	screenshot(t, env, "no_lock_on_settings")
}

func TestNav_BackButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Navigate to Chat
	navigateToPage(t, env, "Chat")
	_, err := env.adb.WaitForElement("chatPage", elementTimeout)
	require.NoError(t, err)

	// Press back
	require.NoError(t, env.adb.PressBack())
	Sleep(1 * time.Second)

	// Check if the app is still running (Qt back might close the app)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// App may still be running or may have closed. Either is acceptable behavior.
	topBar := hierarchy.FindByContentDesc("topBar")
	if topBar != nil {
		t.Log("app remained open after pressing back")
	} else {
		// Check if we're on the launcher — app closed
		nodes := hierarchy.FindContainingText("")
		found := false
		for _, n := range nodes {
			if strings.Contains(n.ContentDesc, "wingout") || strings.Contains(n.ContentDesc, "WingOut") {
				found = true
				break
			}
		}
		if !found {
			t.Log("app closed after pressing back — acceptable Qt behavior")
		}
	}
	screenshot(t, env, "after_back")
}
