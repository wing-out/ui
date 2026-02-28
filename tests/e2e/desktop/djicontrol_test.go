//go:build desktop_e2e

package desktop

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_DJIPageLoads(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")

	node, err := env.atspi.WaitForElement("djiControlPage", elementTimeout)
	require.NoError(t, err, "DJI Control page should be visible")
	require.NotNil(t, node)
	screenshot(t, env, "dji_page")
}

func TestDesktop_DJIDiscoveryButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	btn := tree.FindByName("djiDiscoveryButton")
	require.NotNil(t, btn, "DJI discovery button should exist")
	screenshot(t, env, "dji_discovery_button")
}

func TestDesktop_DJIDiscoveryButtonLabel(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	nodes := tree.FindContainingText("Start Discovery")
	require.NotEmpty(t, nodes, "'Start Discovery' label should be visible")
	screenshot(t, env, "dji_discovery_label")
}

func TestDesktop_DJIDiscoveryButtonClickable(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap discovery button to start
	require.NoError(t, env.atspi.ActivateByName("djiDiscoveryButton"))
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	disconnectNodes := tree.FindContainingText("Disconnect")
	require.NotEmpty(t, disconnectNodes, "after tapping discovery, button should show 'Disconnect'")

	// Tap again to stop
	require.NoError(t, env.atspi.ActivateByName("djiDiscoveryButton"))
	Sleep(1 * time.Second)

	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)
	startNodes := tree.FindContainingText("Start Discovery")
	require.NotEmpty(t, startNodes, "after tapping again, button should show 'Start Discovery'")
	screenshot(t, env, "dji_discovery_toggle")
}

func TestDesktop_DJIWiFiSettingsHeading(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	wifiNodes := tree.FindContainingText("WiFi Settings")
	require.NotEmpty(t, wifiNodes, "'WiFi Settings' heading should be visible")
	screenshot(t, env, "dji_wifi_heading")
}

func TestDesktop_DJIWiFiFields(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	ssidField := tree.FindByName("djiSsidField")
	require.NotNil(t, ssidField, "SSID field should exist")

	pskField := tree.FindByName("djiPskField")
	require.NotNil(t, pskField, "PSK field should exist")
	screenshot(t, env, "dji_wifi_fields")
}

func TestDesktop_DJIWiFiConnectButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	connectBtn := tree.FindByName("djiConnectWifiButton")
	require.NotNil(t, connectBtn, "WiFi connect button should exist")
	screenshot(t, env, "dji_wifi_connect_button")
}

func TestDesktop_DJIWiFiConnectFlow(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Type SSID
	require.NoError(t, env.atspi.ActivateByName("djiSsidField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("TestSSID"))
	Sleep(300 * time.Millisecond)

	// Type PSK
	require.NoError(t, env.atspi.ActivateByName("djiPskField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("TestPassword"))
	Sleep(300 * time.Millisecond)

	// Tap connect
	require.NoError(t, env.atspi.ActivateByName("djiConnectWifiButton"))
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	disconnectNodes := tree.FindContainingText("Disconnect WiFi")
	require.NotEmpty(t, disconnectNodes, "after connecting WiFi, button should show 'Disconnect WiFi'")
	screenshot(t, env, "dji_wifi_connect_flow")
}

func TestDesktop_DJIRtmpField(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	rtmpField := tree.FindByName("djiRtmpField")
	require.NotNil(t, rtmpField, "RTMP URL field should exist")
	screenshot(t, env, "dji_rtmp_field")
}

func TestDesktop_DJIStreamSettingsTiles(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	tiles := []string{"djiResolutionTile", "djiFpsTile", "djiBitrateTile"}
	for _, tile := range tiles {
		t.Run(tile, func(t *testing.T) {
			node := tree.FindByName(tile)
			require.NotNil(t, node, "stream settings tile %q should exist", tile)
		})
	}
	screenshot(t, env, "dji_stream_settings_tiles")
}

func TestDesktop_DJIStreamSettingsHeading(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	nodes := tree.FindContainingText("Stream Settings")
	require.NotEmpty(t, nodes, "'Stream Settings' heading should be visible")
	screenshot(t, env, "dji_stream_settings_heading")
}

func TestDesktop_DJIStreamingHeading(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	nodes := tree.FindContainingText("Streaming")
	require.NotEmpty(t, nodes, "'Streaming' heading should be visible")
	screenshot(t, env, "dji_streaming_heading")
}

func TestDesktop_DJIResolutionSelectors(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	resButtons := []string{"djiRes720p", "djiRes1080p", "djiRes4K"}
	for _, btn := range resButtons {
		t.Run(btn, func(t *testing.T) {
			node := tree.FindByName(btn)
			require.NotNil(t, node, "resolution button %q should exist", btn)
		})
	}
	screenshot(t, env, "dji_resolution_selectors")
}

func TestDesktop_DJIResolutionSelectorInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap 720p
	require.NoError(t, env.atspi.ActivateByName("djiRes720p"))
	Sleep(500 * time.Millisecond)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	resTile := tree.FindByName("djiResolutionTile")
	require.NotNil(t, resTile, "resolution tile should exist after selection")
	screenshot(t, env, "dji_resolution_720p_selected")
}

func TestDesktop_DJIFPSSelectors(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	fpsButtons := []string{"djiFps24", "djiFps30", "djiFps60"}
	for _, btn := range fpsButtons {
		t.Run(btn, func(t *testing.T) {
			node := tree.FindByName(btn)
			require.NotNil(t, node, "FPS button %q should exist", btn)
		})
	}
	screenshot(t, env, "dji_fps_selectors")
}

func TestDesktop_DJIFPSSelectorInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap 60fps
	require.NoError(t, env.atspi.ActivateByName("djiFps60"))
	Sleep(500 * time.Millisecond)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	fpsTile := tree.FindByName("djiFpsTile")
	require.NotNil(t, fpsTile, "FPS tile should exist after selection")
	screenshot(t, env, "dji_fps_60_selected")
}

func TestDesktop_DJIBitrateSelectors(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	bitrateButtons := []string{"djiBitrate4", "djiBitrate8", "djiBitrate12", "djiBitrate20"}
	for _, btn := range bitrateButtons {
		t.Run(btn, func(t *testing.T) {
			node := tree.FindByName(btn)
			require.NotNil(t, node, "bitrate button %q should exist", btn)
		})
	}
	screenshot(t, env, "dji_bitrate_selectors")
}

func TestDesktop_DJIBitrateSelectorInteraction(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap 20Mbps
	require.NoError(t, env.atspi.ActivateByName("djiBitrate20"))
	Sleep(500 * time.Millisecond)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	bitrateTile := tree.FindByName("djiBitrateTile")
	require.NotNil(t, bitrateTile, "bitrate tile should exist after selection")
	screenshot(t, env, "dji_bitrate_20_selected")
}

func TestDesktop_DJIStreamButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	streamBtn := tree.FindByName("djiStreamButton")
	require.NotNil(t, streamBtn, "DJI stream button should exist")

	startNodes := tree.FindContainingText("Start Stream")
	require.NotEmpty(t, startNodes, "'Start Stream' label should be visible")
	screenshot(t, env, "dji_stream_button")
}

func TestDesktop_DJILogArea(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	logArea := tree.FindByName("djiLogArea")
	require.NotNil(t, logArea, "DJI log area should exist")
	screenshot(t, env, "dji_log_area")
}

func TestDesktop_DJILogUpdatesOnActions(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Perform an action to generate log entries
	require.NoError(t, env.atspi.ActivateByName("djiDiscoveryButton"))
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	logArea := tree.FindByName("djiLogArea")
	require.NotNil(t, logArea, "log area should exist after action")
	// Check that log has some content
	texts := logArea.GetAllTexts()
	require.NotEmpty(t, texts, "log area should contain text after performing actions")
	screenshot(t, env, "dji_log_after_action")

	// Stop discovery
	require.NoError(t, env.atspi.ActivateByName("djiDiscoveryButton"))
	Sleep(500 * time.Millisecond)
}

func TestDesktop_DJIStreamSettingsValues(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Default resolution should be visible (1080p is typically default)
	resNodes := tree.FindContainingText("1080")
	require.NotEmpty(t, resNodes, "resolution value (1080) should be visible")

	// Default FPS should be visible (30 is typically default)
	fpsNodes := tree.FindContainingText("30")
	require.NotEmpty(t, fpsNodes, "FPS value (30) should be visible")
	screenshot(t, env, "dji_settings_values")
}
