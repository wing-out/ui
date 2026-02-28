//go:build desktop_e2e

package desktop

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDesktop_DashboardPageLoads(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	node, err := env.atspi.WaitForElement("dashboardPage", elementTimeout)
	require.NoError(t, err, "dashboard page should be visible after setup")
	require.NotNil(t, node)
	screenshot(t, env, "dashboard_page")
}

func TestDesktop_DashboardMetricTiles(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	tiles := []string{
		"inputBitrateTile",
		"outputBitrateTile",
		"latencyTile",
		"fpsTile",
		"pingTile",
		"qualityTile",
		"cpuTile",
		"memoryTile",
	}

	for _, tile := range tiles {
		t.Run(tile, func(t *testing.T) {
			node := tree.FindByName(tile)
			require.NotNil(t, node, "metric tile %q should be visible", tile)
		})
	}
	screenshot(t, env, "all_tiles")
}

func TestDesktop_BitrateValues(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Mock returns input=6M, output=4.5M
	waitForMetricValue(t, env, "inputBitrateTile", "6.0", 5*time.Second)
	waitForMetricValue(t, env, "outputBitrateTile", "4.5", 5*time.Second)
	screenshot(t, env, "bitrate_values")
}

func TestDesktop_LatencyValues(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Mock: sending=3500us + transcoding=2000us = 5.5ms total
	waitForMetricValue(t, env, "latencyTile", "5.5", 5*time.Second)
	screenshot(t, env, "latency_value")
}

func TestDesktop_FPSValue(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Mock: 30000/1001 = 29.97 -> toFixed(1) = "30.0"
	waitForMetricValue(t, env, "fpsTile", "30.0", 5*time.Second)
	screenshot(t, env, "fps_value")
}

func TestDesktop_ContinuityValue(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Mock: continuity=0.998 -> displayed as "99.8"
	waitForMetricValue(t, env, "qualityTile", "99.8", 5*time.Second)
	screenshot(t, env, "continuity_value")
}

func TestDesktop_UptimeSection(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	// CPU and Memory tiles should show "0" since platform controller returns 0
	cpuTexts := getMetricTileValue(t, env, "cpuTile")
	require.NotNil(t, cpuTexts, "CPU tile should have text content")
	memTexts := getMetricTileValue(t, env, "memoryTile")
	require.NotNil(t, memTexts, "Memory tile should have text content")

	cpuJoined := strings.Join(cpuTexts, " ")
	memJoined := strings.Join(memTexts, " ")
	require.Contains(t, cpuJoined, "0", "CPU tile should show 0")
	require.Contains(t, memJoined, "0", "Memory tile should show 0")
	screenshot(t, env, "cpu_memory")
}

func TestDesktop_PlatformBadges(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	badges := []string{"twitchBadge", "youtubeBadge", "kickBadge"}
	for _, badge := range badges {
		t.Run(badge, func(t *testing.T) {
			node := tree.FindByName(badge)
			require.NotNil(t, node, "badge %q should be visible", badge)
		})
	}
	screenshot(t, env, "platform_badges")
}

func TestDesktop_DynamicBitrateUpdate(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	// Initially mock returns 6M
	waitForMetricValue(t, env, "inputBitrateTile", "6.0", 5*time.Second)

	// Change mock to 3M
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 3000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 2000000, Audio: 128000},
		}, nil
	}

	// Wait for UI to update
	waitForMetricValue(t, env, "inputBitrateTile", "3.0", 5*time.Second)
	screenshot(t, env, "dynamic_bitrate_update")

	// Restore original mock
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 6000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 4500000, Audio: 128000},
		}, nil
	}
}

func TestDesktop_DiagnosticsTilesPresent(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	diagnosticsTiles := []string{
		"signalStrengthTile",
		"viewersTotalTile",
		"playerLagTile",
		"outputFpsTile",
	}

	for _, tile := range diagnosticsTiles {
		t.Run(tile, func(t *testing.T) {
			node := tree.FindByName(tile)
			require.NotNil(t, node, "diagnostics tile %q should be visible", tile)
		})
	}
	screenshot(t, env, "diagnostics_tiles")
}

func TestDesktop_PlatformBadgeLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Verify badge labels contain platform names
	require.NotEmpty(t, tree.FindContainingText("Twitch"), "Twitch badge label should be visible")
	require.NotEmpty(t, tree.FindContainingText("YouTube"), "YouTube badge label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Kick"), "Kick badge label should be visible")
	screenshot(t, env, "platform_badge_labels")
}

func TestDesktop_StreamMetricsHeading(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	nodes := tree.FindContainingText("Stream Metrics")
	require.NotEmpty(t, nodes, "'Stream Metrics' heading should be visible on dashboard")
	screenshot(t, env, "stream_metrics_heading")
}

func TestDesktop_SystemHeading(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	nodes := tree.FindContainingText("System")
	require.NotEmpty(t, nodes, "'System' heading should be visible on dashboard")
	screenshot(t, env, "system_heading")
}

func TestDesktop_DiagnosticsInjectionCalled(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	env.mockFF.ResetCallCounts()
	time.Sleep(3 * time.Second)

	count := env.mockFF.CallCount("InjectDiagnostics")
	require.GreaterOrEqual(t, count, 1, "InjectDiagnostics should be called periodically, got %d", count)
	t.Logf("InjectDiagnostics called %d times in 3s", count)
}

func TestDesktop_PlayerLagValue(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	// Mock returns PlayerGetLag = 1.5
	texts := getMetricTileValue(t, env, "playerLagTile")
	require.NotNil(t, texts, "playerLagTile should have content")
	joined := strings.Join(texts, " ")
	require.Contains(t, joined, "1.5", "player lag tile should show 1.5s lag value")
	screenshot(t, env, "player_lag_value")
}

func TestDesktop_StreamActiveBadge(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	badge := tree.FindByName("streamActiveBadge")
	require.NotNil(t, badge, "streamActiveBadge should be present on dashboard")
	screenshot(t, env, "stream_active_badge")
}
