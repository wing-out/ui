//go:build android_e2e

package android

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDashboard_PageLoads(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Dashboard is the landing page (index 0)
	node, err := env.adb.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboardPage should be visible as the landing page")
	require.NotNil(t, node)
	screenshot(t, env, "dashboard_loads")
}

func TestDashboard_IsFirstPage(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	// Verify Dashboard is the landing page after setup
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	pageTitle := hierarchy.FindByContentDescPrefix("pageTitle")
	require.NotNil(t, pageTitle, "page title should be visible")
	require.Contains(t, pageTitle.ContentDesc, "Dashboard",
		"landing page should be Dashboard")
	screenshot(t, env, "dashboard_is_first")
}

func TestDashboard_VideoPreviewPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	videoPreview := hierarchy.FindByContentDesc("dashboardVideoPreview")
	require.NotNil(t, videoPreview, "video preview should be present on dashboard")
	screenshot(t, env, "dashboard_video_preview")
}

func TestDashboard_PlatformBadgesPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	badges := []string{"dashboardTwitchBadge", "dashboardYoutubeBadge", "dashboardKickBadge"}
	for _, badge := range badges {
		t.Run(badge, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(badge)
			require.NotNil(t, node, "badge %q should be visible on dashboard", badge)
		})
	}
	screenshot(t, env, "dashboard_platform_badges")
}

func TestDashboard_CompactMetricsPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	compactMetrics := hierarchy.FindByContentDesc("dashboardCompactMetrics")
	require.NotNil(t, compactMetrics, "compact metrics row should be present on dashboard")
	screenshot(t, env, "dashboard_compact_metrics")
}

func TestDashboard_ChatVisible(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	chatView := hierarchy.FindByContentDesc("dashboardChat")
	require.NotNil(t, chatView, "chat view should be present on dashboard")
	screenshot(t, env, "dashboard_chat")
}
