//go:build android_e2e

package android

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestStatus_AllTilesPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Stream Metrics tiles
	tiles := []string{
		"inputBitrateTile",
		"outputBitrateTile",
		"latencyTile",
		"fpsTile",
		"pingTile",
		"qualityTile",
	}
	for _, tile := range tiles {
		t.Run(tile, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(tile)
			require.NotNil(t, node, "metric tile %q should be visible", tile)
		})
	}

	// System tiles
	systemTiles := []string{"cpuTile", "memoryTile"}
	for _, tile := range systemTiles {
		t.Run(tile, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(tile)
			require.NotNil(t, node, "system tile %q should be visible", tile)
		})
	}
	screenshot(t, env, "all_tiles")
}

func TestStatus_DiagnosticsTilesPresent(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	// Scroll down to Diagnostics section
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	diagnosticTiles := []string{
		"signalStrengthTile",
		"viewersTotalTile",
		"playerLagTile",
		"outputFpsTile",
	}
	for _, tile := range diagnosticTiles {
		t.Run(tile, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(tile)
			if node == nil {
				// May need more scrolling
				env.adb.Swipe(500, 600, 500, 100, 300)
				Sleep(300 * time.Millisecond)
				hierarchy, _ = env.adb.DumpUI()
				node = hierarchy.FindByContentDesc(tile)
			}
			require.NotNil(t, node, "diagnostic tile %q should be visible", tile)
		})
	}
	screenshot(t, env, "diagnostics_tiles")
}

func TestStatus_BitrateValues(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Mock returns input=6M, output=4.5M
	waitForMetricValue(t, env, "inputBitrateTile", "6.0", 5*time.Second)
	waitForMetricValue(t, env, "outputBitrateTile", "4.5", 5*time.Second)
	screenshot(t, env, "bitrate_values")
}

func TestStatus_LatencyValue(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Mock: sending=3500us + transcoding=2000us = 5.5ms total
	waitForMetricValue(t, env, "latencyTile", "5.5", 5*time.Second)
	screenshot(t, env, "latency_value")
}

func TestStatus_FPSValue(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Mock: 30000/1001 = 29.97 -> toFixed(1) = "30.0"
	waitForMetricValue(t, env, "fpsTile", "30.0", 5*time.Second)
	screenshot(t, env, "fps_value")
}

func TestStatus_PingRTT(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Ping should return non-empty value
	Sleep(3 * time.Second)
	texts := getMetricTileValue(t, env, "pingTile")
	joined := strings.Join(texts, " ")
	require.NotEmpty(t, texts, "ping tile should have text content")
	t.Logf("ping tile shows: %s", joined)
	screenshot(t, env, "ping_value")
}

func TestStatus_ContinuityValue(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Mock: continuity=0.998 -> displayed as "99.8"
	waitForMetricValue(t, env, "qualityTile", "99.8", 5*time.Second)
	screenshot(t, env, "continuity_value")
}

func TestStatus_CpuMemoryTiles(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	cpuTexts := getMetricTileValue(t, env, "cpuTile")
	require.NotNil(t, cpuTexts, "CPU tile should have text content")
	memTexts := getMetricTileValue(t, env, "memoryTile")
	require.NotNil(t, memTexts, "Memory tile should have text content")

	// CPU and memory should show a percentage value (0-100)
	cpuJoined := strings.Join(cpuTexts, " ")
	memJoined := strings.Join(memTexts, " ")
	require.NotEmpty(t, cpuJoined, "CPU tile should have a value")
	require.NotEmpty(t, memJoined, "Memory tile should have a value")
	t.Logf("CPU tile: %s, Memory tile: %s", cpuJoined, memJoined)
	screenshot(t, env, "cpu_memory")
}

func TestStatus_PlatformBadges(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	badges := []string{"twitchBadge", "youtubeBadge", "kickBadge"}
	for _, badge := range badges {
		t.Run(badge, func(t *testing.T) {
			node := hierarchy.FindByContentDesc(badge)
			require.NotNil(t, node, "badge %q should be visible", badge)
		})
	}
	screenshot(t, env, "platform_badges")
}

func TestStatus_PlatformBadgeLabels(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotNil(t, hierarchy.FindByContentDesc("twitchBadge"), "Twitch badge should exist")
	require.NotNil(t, hierarchy.FindByContentDesc("youtubeBadge"), "YouTube badge should exist")
	require.NotNil(t, hierarchy.FindByContentDesc("kickBadge"), "Kick badge should exist")
	screenshot(t, env, "platform_badge_labels")
}

func TestStatus_StreamMetricsHeading(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	metricsNodes := hierarchy.FindContainingText("Stream Metrics")
	require.NotEmpty(t, metricsNodes, "Stream Metrics heading should be visible")
	screenshot(t, env, "stream_metrics_heading")
}

func TestStatus_SystemHeading(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	systemNodes := hierarchy.FindContainingText("System")
	require.NotEmpty(t, systemNodes, "System heading should be visible")
	screenshot(t, env, "system_heading")
}

func TestStatus_DynamicBitrateUpdate(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

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

func TestStatus_DynamicLatencyUpdate(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Initially 5.5ms
	waitForMetricValue(t, env, "latencyTile", "5.5", 5*time.Second)

	// Change mock to sending=10000us + transcoding=5000us = 15ms
	env.mockFF.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{SendingUs: 10000, TranscodingUs: 5000},
		}, nil
	}

	waitForMetricValue(t, env, "latencyTile", "15.0", 5*time.Second)
	screenshot(t, env, "dynamic_latency_update")

	// Restore original mock
	env.mockFF.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{SendingUs: 3500, PreTranscodingUs: 1500, TranscodingUs: 2000},
		}, nil
	}
}

func TestStatus_BackendCallFrequency(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	// Reset call counts and wait
	env.mockFF.ResetCallCounts()
	time.Sleep(2 * time.Second)

	// The status page polls periodically; we expect several calls
	callCount := env.mockFF.CallCount("GetBitRates")
	require.Greater(t, callCount, 5, "GetBitRates should have been called >5 times in 2s, got %d", callCount)
	t.Logf("GetBitRates called %d times in 2s", callCount)
}

func TestStatus_DiagnosticsInjectionCalled(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	// Reset call counts and wait for diagnostics injection timer (1s interval)
	env.mockFF.ResetCallCounts()
	time.Sleep(3 * time.Second)

	callCount := env.mockFF.CallCount("InjectDiagnostics")
	require.GreaterOrEqual(t, callCount, 1,
		"InjectDiagnostics should have been called at least once in 3s, got %d", callCount)
	t.Logf("InjectDiagnostics called %d times in 3s", callCount)
	screenshot(t, env, "diagnostics_injection")
}

func TestStatus_UptimeSection(t *testing.T) {
	env := sharedEnv

	// Set mock to return active stream to trigger the uptime section
	viewers := uint64(10)
	env.mockSD.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		return &backend.StreamStatus{IsActive: true, ViewersCount: &viewers}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	// Wait for stream status polling
	Sleep(7 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// The "LIVE" badge is shown via streamActiveBadge when streamActive is true
	liveBadge := hierarchy.FindByContentDesc("streamActiveBadge")
	if liveBadge != nil {
		t.Log("LIVE badge found, stream is active")
	}

	// Look for streamActiveBadge or Uptime text in content-desc
	uptimeNodes := hierarchy.FindContainingText("Uptime")

	// At least one of these should be visible if the stream is active
	hasLive := liveBadge != nil || len(uptimeNodes) > 0
	require.True(t, hasLive, "LIVE badge or Uptime text should be visible when stream is active")

	screenshot(t, env, "status_uptime")

	// Restore default
	env.mockSD.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		v := uint64(42)
		return &backend.StreamStatus{IsActive: true, ViewersCount: &v}, nil
	}
}

func TestStatus_DiagnosticsSection(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")
	Sleep(2 * time.Second)

	// Scroll down to Diagnostics section
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Check for Diagnostics heading
	diagNodes := hierarchy.FindContainingText("Diagnostics")
	if len(diagNodes) == 0 {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(500 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		diagNodes = hierarchy.FindContainingText("Diagnostics")
	}
	require.NotEmpty(t, diagNodes, "Diagnostics section heading should be visible")

	// Verify signal strength tile
	signalTile := hierarchy.FindByContentDesc("signalStrengthTile")
	require.NotNil(t, signalTile, "Signal Strength tile should exist")

	// Verify total viewers tile
	viewersTile := hierarchy.FindByContentDesc("viewersTotalTile")
	require.NotNil(t, viewersTile, "Total Viewers tile should exist")

	// Verify player lag tile
	playerLagTile := hierarchy.FindByContentDesc("playerLagTile")
	require.NotNil(t, playerLagTile, "Player Lag tile should exist")

	// Verify output FPS tile
	outputFpsTile := hierarchy.FindByContentDesc("outputFpsTile")
	require.NotNil(t, outputFpsTile, "Output FPS tile should exist")

	screenshot(t, env, "status_diagnostics")
}

func TestStatus_ViewerCountFromBackend(t *testing.T) {
	env := sharedEnv

	// Set mock to return specific viewer counts
	env.mockSD.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		v := uint64(100)
		return &backend.StreamStatus{IsActive: true, ViewersCount: &v}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Wait for stream status polling (interval is 5000ms)
	Sleep(7 * time.Second)

	// Scroll down to see Total Viewers tile
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// The total viewers tile should show 300 (100 per platform x 3 platforms)
	viewersTile := hierarchy.FindByContentDesc("viewersTotalTile")
	if viewersTile == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(500 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		viewersTile = hierarchy.FindByContentDesc("viewersTotalTile")
	}
	require.NotNil(t, viewersTile, "Total Viewers tile should exist")

	texts := getMetricTileValue(t, env, "viewersTotalTile")
	joined := strings.Join(texts, " ")
	// Each platform returns 100 viewers, total = 300
	require.Contains(t, joined, "300", "Total Viewers tile should show 300 (100 per platform)")

	screenshot(t, env, "status_viewer_count")

	// Restore default
	env.mockSD.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		v := uint64(42)
		return &backend.StreamStatus{IsActive: true, ViewersCount: &v}, nil
	}
}

func TestStatus_PlayerLagValue(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Status")

	// Wait for player lag polling (500ms interval)
	Sleep(3 * time.Second)

	// Scroll down to Diagnostics section
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	texts := getMetricTileValue(t, env, "playerLagTile")
	if texts == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(500 * time.Millisecond)
		texts = getMetricTileValue(t, env, "playerLagTile")
	}
	require.NotNil(t, texts, "Player Lag tile should have text content")
	t.Logf("player lag tile shows: %s", strings.Join(texts, " "))
	screenshot(t, env, "player_lag_value")
}
