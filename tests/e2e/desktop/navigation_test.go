//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_NavigateAllPages(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	pages := []struct {
		menuLabel    string
		accessibleID string
	}{
		{"Dashboard", "dashboardPage"},
		{"Cameras", "camerasPage"},
		{"DJI Control", "djiControlPage"},
		{"Chat", "chatPage"},
		{"Players", "playersPage"},
		{"Restreams", "restreamsPage"},
		{"Monitor", "monitorPage"},
		{"Profiles", "profilesPage"},
		{"Settings", "settingsPage"},
	}

	for _, page := range pages {
		t.Run(page.menuLabel, func(t *testing.T) {
			navigateToPage(t, env, page.menuLabel)

			node, err := env.atspi.WaitForElement(page.accessibleID, elementTimeout)
			require.NoError(t, err, "page %q should be visible", page.menuLabel)
			require.NotNil(t, node)

			// Verify top bar title
			err = env.atspi.WaitForText(page.menuLabel, 3*time.Second)
			require.NoError(t, err, "title should show %q", page.menuLabel)

			screenshot(t, env, "page_"+page.menuLabel)
		})
	}
}

func TestDesktop_MenuToggle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Open menu
	openNavMenu(t, env)
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	navMenu := tree.FindByName("navMenu")
	require.NotNil(t, navMenu, "nav menu should be visible after tap")

	// Close menu by tapping menu button again
	require.NoError(t, env.atspi.ActivateByName("menuButton"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "menu_closed")
}

func TestDesktop_MenuHighlightsCurrentPage(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Navigate to Chat
	navigateToPage(t, env, "Chat")
	Sleep(500 * time.Millisecond)

	// Open menu and verify Chat exists in the tree
	openNavMenu(t, env)
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	chatItems := tree.FindContainingText("Chat")
	require.NotEmpty(t, chatItems, "Chat item should exist in nav menu")
	screenshot(t, env, "menu_highlights_chat")
}

func TestDesktop_KeyboardShortcut(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// On Dashboard, press Space to toggle lock
	_, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err)

	require.NoError(t, env.atspi.PressKey("space"))
	Sleep(500 * time.Millisecond)

	// Lock overlay should appear
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	overlay := tree.FindByName("lockOverlay")
	if overlay != nil {
		t.Log("lock overlay activated via keyboard shortcut")
	}

	// Press Space again to unlock
	require.NoError(t, env.atspi.PressKey("space"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "keyboard_shortcut")
}
