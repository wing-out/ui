//go:build android_e2e

package android

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestThemes_AllPagesAllThemes(t *testing.T) {
	env := sharedEnv

	themes := []string{"dark", "light", "wingout-dark", "wingout-light", "midnight", "amoled"}
	pages := []string{"Dashboard", "Status", "Cameras", "DJI Control", "Chat", "Players", "Restreams", "Monitor", "Profiles", "Logs", "Settings"}

	for _, theme := range themes {
		theme := theme
		t.Run(theme, func(t *testing.T) {
			// Fresh app state for each theme to avoid stale scroll position
			resetApp(t, env)
			completeSetup(t, env)

			// Navigate to Settings — theme buttons are at the top, visible on fresh page
			navigateToPage(t, env, "Settings")
			Sleep(500 * time.Millisecond)

			themeAccessible := "theme_" + theme
			node, err := env.adb.WaitForElement(themeAccessible, 10*time.Second)
			if err != nil {
				// Debug: dump visible elements
				hierarchy, dumpErr := env.adb.DumpUI()
				if dumpErr == nil {
					logThemeButtons(t, hierarchy)
				}
				t.Fatalf("theme button %q not found: %v", themeAccessible, err)
			}
			require.NoError(t, env.adb.TapNode(node))
			Sleep(500 * time.Millisecond)

			for _, page := range pages {
				page := page
				t.Run(page, func(t *testing.T) {
					navigateToPage(t, env, page)
					Sleep(500 * time.Millisecond)
					screenshot(t, env, theme+"_"+page)

					if page == "Settings" {
						env.adb.Swipe(500, 600, 500, 100, 300)
						Sleep(500 * time.Millisecond)
						screenshot(t, env, theme+"_"+page+"_scrolled1")

						env.adb.Swipe(500, 600, 500, 100, 300)
						Sleep(500 * time.Millisecond)
						screenshot(t, env, theme+"_"+page+"_scrolled2")
					}
				})
			}
		})
	}
}

// logThemeButtons dumps content-desc values containing "theme_" for debugging.
func logThemeButtons(t *testing.T, h *UIHierarchy) {
	t.Helper()
	var count int
	for i := range h.Nodes {
		logMatchingNodes(t, &h.Nodes[i], &count)
	}
	if count == 0 {
		t.Log("no nodes with 'theme_' in content-desc found")
	}
}

func logMatchingNodes(t *testing.T, node *UINode, count *int) {
	t.Helper()
	if node.ContentDesc != "" {
		t.Logf("  content-desc=%q bounds=%s", node.ContentDesc, node.Bounds)
		*count++
	}
	for i := range node.Children {
		logMatchingNodes(t, &node.Children[i], count)
	}
}
