//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_MonitorPageLoads(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")

	node, err := env.atspi.WaitForElement("monitorPage", elementTimeout)
	require.NoError(t, err, "monitor page should be visible")
	require.NotNil(t, node)
	screenshot(t, env, "monitor_page")
}

func TestDesktop_StreamInfoTiles(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Stream Monitor"), "Stream Monitor title should be visible")
	require.NotEmpty(t, tree.FindContainingText("No preview available"), "no preview message should be visible")
	require.NotEmpty(t, tree.FindContainingText("Stream Info"), "Stream Info section should be visible")
	screenshot(t, env, "monitor_info_tiles")
}

func TestDesktop_MonitorPlayPauseButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	playPauseBtn := tree.FindByName("monitorPlayPauseBtn")
	require.NotNil(t, playPauseBtn, "monitor play/pause button should exist")
	screenshot(t, env, "monitor_play_pause_btn")
}

func TestDesktop_MonitorStopButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	stopBtn := tree.FindByName("monitorStopBtn")
	require.NotNil(t, stopBtn, "monitor stop button should exist")
	screenshot(t, env, "monitor_stop_btn")
}

func TestDesktop_MonitorMuteButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	muteBtn := tree.FindByName("monitorMuteBtn")
	require.NotNil(t, muteBtn, "monitor mute button should exist")
	screenshot(t, env, "monitor_mute_btn")
}

func TestDesktop_MonitorPlayPauseToggle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	// Tap play button
	require.NoError(t, env.atspi.ActivateByName("monitorPlayPauseBtn"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "monitor_after_play")

	// Tap again to pause
	require.NoError(t, env.atspi.ActivateByName("monitorPlayPauseBtn"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "monitor_after_pause")
}

func TestDesktop_MonitorMuteToggle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	// Tap mute button to toggle
	require.NoError(t, env.atspi.ActivateByName("monitorMuteBtn"))
	Sleep(500 * time.Millisecond)

	// Tap again to unmute
	require.NoError(t, env.atspi.ActivateByName("monitorMuteBtn"))
	Sleep(500 * time.Millisecond)
	screenshot(t, env, "monitor_mute_toggle")
}

func TestDesktop_MonitorResolutionTile(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	resTile := tree.FindByName("monitorResolutionTile")
	require.NotNil(t, resTile, "Resolution tile should exist")
	screenshot(t, env, "monitor_resolution_tile")
}

func TestDesktop_MonitorCodecTile(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	codecTile := tree.FindByName("monitorCodecTile")
	require.NotNil(t, codecTile, "Codec tile should exist")
	screenshot(t, env, "monitor_codec_tile")
}

func TestDesktop_MonitorStreamInfoDefault(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Stream info should show default/empty values
	resNodes := tree.FindContainingText("--")
	require.NotEmpty(t, resNodes, "stream info tiles should show '--' when no stream is active")
	screenshot(t, env, "monitor_info_default")
}

func TestDesktop_MonitorSourceSelectorPresent(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// The source selector row is visible when sources.length > 1
	// Mock returns cam0 and cam1
	sourceLabel := tree.FindContainingText("Source:")
	require.NotEmpty(t, sourceLabel, "Source: label should be visible when multiple sources exist")

	cam0Btn := tree.FindByName("monitorSourceBtn_cam0")
	require.NotNil(t, cam0Btn, "cam0 source button should exist in selector")

	cam1Btn := tree.FindByName("monitorSourceBtn_cam1")
	require.NotNil(t, cam1Btn, "cam1 source button should exist in selector")
	screenshot(t, env, "monitor_source_selector")
}

func TestDesktop_MonitorSourceSelectorSwitches(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(2 * time.Second)

	// Tap cam1 source button
	require.NoError(t, env.atspi.ActivateByName("monitorSourceBtn_cam1"))
	Sleep(1 * time.Second)

	// Verify the selected source text changes
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	selectedNodes := tree.FindContainingText("cam1")
	require.NotEmpty(t, selectedNodes, "selected source should show cam1 after tapping")
	screenshot(t, env, "monitor_source_switch")
}

func TestDesktop_MonitorSelectedSourceText(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Monitor")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	selectedNodes := tree.FindContainingText("Selected Source:")
	require.NotEmpty(t, selectedNodes, "'Selected Source:' text should be visible")
	screenshot(t, env, "monitor_selected_source_text")
}

func TestDesktop_MonitorSourceDataFromBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	env.mockSD.ResetCallCounts()
	navigateToPage(t, env, "Monitor")
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ListStreamSources"), 1,
		"ListStreamSources should have been called by the Monitor page")

	// Verify selected source text appears
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	selectedNodes := tree.FindContainingText("cam0")
	require.NotEmpty(t, selectedNodes, "selected source cam0 should appear in the page")
	screenshot(t, env, "monitor_source_data")
}
