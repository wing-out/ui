//go:build android_e2e

package android

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDJI_PageStructure(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")

	node, err := env.adb.WaitForElement("djiControlPage", elementTimeout)
	require.NoError(t, err)
	require.NotNil(t, node)
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Check title
	titleNodes := hierarchy.FindContainingText("DJI Camera Control")
	require.NotEmpty(t, titleNodes, "DJI Camera Control title should be visible")

	// Check discovery button
	discoveryBtn := hierarchy.FindByContentDesc("djiDiscoveryButton")
	require.NotNil(t, discoveryBtn, "Discovery button should exist (objectName)")

	screenshot(t, env, "dji_structure")
}

func TestDJI_DiscoveryButtonLabel(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Initially not paired, so button says "Start Discovery"
	discoveryNodes := hierarchy.FindContainingText("Start Discovery")
	require.NotEmpty(t, discoveryNodes, "Start Discovery button label should be visible")
	screenshot(t, env, "dji_discovery_label")
}

func TestDJI_DiscoveryButtonClickable(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap discovery button
	discoveryBtn, err := env.adb.WaitForElement("djiDiscoveryButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(discoveryBtn))
	Sleep(500 * time.Millisecond)

	// After tapping, the button should change to "Disconnect" (simulated pairing)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	disconnectNodes := hierarchy.FindContainingText("Disconnect")
	require.NotEmpty(t, disconnectNodes, "After tapping discovery, button should show 'Disconnect' (simulated pair)")

	// Tap again to disconnect
	discoveryBtn, err = env.adb.WaitForElement("djiDiscoveryButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(discoveryBtn))
	Sleep(500 * time.Millisecond)

	hierarchy, err = env.adb.DumpUI()
	require.NoError(t, err)
	startNodes := hierarchy.FindContainingText("Start Discovery")
	require.NotEmpty(t, startNodes, "After disconnecting, button should show 'Start Discovery' again")
	screenshot(t, env, "dji_discovery_clickable")
}

func TestDJI_StatusBadges(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("Not Paired"), "BLE status 'Not Paired' should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("No WiFi"), "WiFi status 'No WiFi' should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("Idle"), "Stream status 'Idle' should be visible")
	screenshot(t, env, "dji_badges")
}

func TestDJI_WiFiSSIDField(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("djiSsidField", elementTimeout)
	require.NoError(t, err, "WiFi SSID input field should exist")
	require.NotNil(t, node)
	screenshot(t, env, "dji_ssid_field")
}

func TestDJI_WiFiPSKField(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("djiPskField", elementTimeout)
	require.NoError(t, err, "WiFi PSK input field should exist")
	require.NotNil(t, node)
	screenshot(t, env, "dji_psk_field")
}

func TestDJI_WiFiConnectButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	node, err := env.adb.WaitForElement("djiConnectWifiButton", elementTimeout)
	require.NoError(t, err, "WiFi Connect button should exist")
	require.NotNil(t, node)

	// Initially says "Connect WiFi"
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	connectNodes := hierarchy.FindContainingText("Connect WiFi")
	require.NotEmpty(t, connectNodes, "WiFi connect button should show 'Connect WiFi'")
	screenshot(t, env, "dji_wifi_connect_button")
}

func TestDJI_WiFiConnectFlow(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Type SSID
	ssidField, err := env.adb.WaitForElement("djiSsidField", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(ssidField))
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.TypeText("TestNetwork"))
	Sleep(500 * time.Millisecond)
	require.NoError(t, env.adb.PressBack())
	Sleep(500 * time.Millisecond)

	// Tap Connect WiFi
	wifiBtn, err := env.adb.WaitForElement("djiConnectWifiButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(wifiBtn))
	Sleep(500 * time.Millisecond)

	// Should now show "Disconnect WiFi"
	_, err = env.adb.WaitForTextContaining("Disconnect WiFi", 5*time.Second)
	require.NoError(t, err, "After connecting, button should show 'Disconnect WiFi'")

	// WiFi status badge should change
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	wifiNodes := hierarchy.FindContainingText("WiFi")
	require.NotEmpty(t, wifiNodes, "WiFi badge should be visible")
	screenshot(t, env, "dji_wifi_connect_flow")
}

func TestDJI_RTMPURLField(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// May need to scroll to see the RTMP field
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	node, err := env.adb.WaitForElement("djiRtmpField", elementTimeout)
	require.NoError(t, err, "RTMP URL input field should exist")
	require.NotNil(t, node)
	screenshot(t, env, "dji_rtmp_field")
}

func TestDJI_StreamSettingsTiles(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll down to see stream settings
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Check objectName-based tiles
	resTile := hierarchy.FindByContentDesc("djiResolutionTile")
	if resTile == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		resTile = hierarchy.FindByContentDesc("djiResolutionTile")
	}
	require.NotNil(t, resTile, "Resolution tile should exist")

	fpsTile := hierarchy.FindByContentDesc("djiFpsTile")
	require.NotNil(t, fpsTile, "FPS tile should exist")

	bitrateTile := hierarchy.FindByContentDesc("djiBitrateTile")
	require.NotNil(t, bitrateTile, "Bitrate tile should exist")

	screenshot(t, env, "dji_settings_tiles")
}

func TestDJI_StreamSettingsValues(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("1080p"), "resolution tile should show 1080p")
	require.NotEmpty(t, hierarchy.FindContainingText("30"), "FPS tile should show 30")
	screenshot(t, env, "dji_settings_values")
}

func TestDJI_ResolutionSelector(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll down to reach resolution selectors
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Resolution buttons: djiRes720p, djiRes1080p, djiRes4K
	res720 := hierarchy.FindByContentDesc("djiRes720p")
	if res720 == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		res720 = hierarchy.FindByContentDesc("djiRes720p")
	}
	require.NotNil(t, res720, "720p resolution button should exist")

	res1080 := hierarchy.FindByContentDesc("djiRes1080p")
	require.NotNil(t, res1080, "1080p resolution button should exist")

	res4k := hierarchy.FindByContentDesc("djiRes4K")
	require.NotNil(t, res4k, "4K resolution button should exist")

	screenshot(t, env, "dji_resolution_selector")
}

func TestDJI_ResolutionSelectorInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll to 720p button ensuring valid bounds
	res720 := scrollToElement(t, env, "djiRes720p")
	require.NoError(t, env.adb.TapNode(res720))
	Sleep(500 * time.Millisecond)

	// The resolution tile should now show 720p
	texts := getMetricTileValue(t, env, "djiResolutionTile")
	require.NotNil(t, texts, "Resolution tile should exist")
	joined := strings.Join(texts, " ")
	require.Contains(t, joined, "720p", "Resolution tile should show 720p after selecting it")
	screenshot(t, env, "dji_resolution_selector_interaction")
}

func TestDJI_FPSSelector(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll down to reach FPS selectors
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// FPS buttons: djiFps24, djiFps30, djiFps60
	fps24 := hierarchy.FindByContentDesc("djiFps24")
	if fps24 == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		fps24 = hierarchy.FindByContentDesc("djiFps24")
	}
	require.NotNil(t, fps24, "24 FPS button should exist")

	fps30 := hierarchy.FindByContentDesc("djiFps30")
	require.NotNil(t, fps30, "30 FPS button should exist")

	fps60 := hierarchy.FindByContentDesc("djiFps60")
	require.NotNil(t, fps60, "60 FPS button should exist")

	screenshot(t, env, "dji_fps_selector")
}

func TestDJI_FPSSelectorInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	// Tap 60 FPS
	fps60, err := env.adb.WaitForElement("djiFps60", elementTimeout)
	if err != nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		fps60, err = env.adb.WaitForElement("djiFps60", elementTimeout)
	}
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(fps60))
	Sleep(500 * time.Millisecond)

	// Verify the FPS tile shows 60
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	require.NotEmpty(t, hierarchy.FindContainingText("60"), "FPS tile should show 60 after selecting it")
	screenshot(t, env, "dji_fps_selector_interaction")
}

func TestDJI_BitrateSelector(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll down to bitrate selectors
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Bitrate buttons: djiBitrate4, djiBitrate8, djiBitrate12, djiBitrate20
	bitrate4 := hierarchy.FindByContentDesc("djiBitrate4")
	if bitrate4 == nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		bitrate4 = hierarchy.FindByContentDesc("djiBitrate4")
	}
	require.NotNil(t, bitrate4, "4 Mbps bitrate button should exist")

	bitrate8 := hierarchy.FindByContentDesc("djiBitrate8")
	require.NotNil(t, bitrate8, "8 Mbps bitrate button should exist")

	bitrate12 := hierarchy.FindByContentDesc("djiBitrate12")
	require.NotNil(t, bitrate12, "12 Mbps bitrate button should exist")

	bitrate20 := hierarchy.FindByContentDesc("djiBitrate20")
	require.NotNil(t, bitrate20, "20 Mbps bitrate button should exist")

	screenshot(t, env, "dji_bitrate_selector")
}

func TestDJI_BitrateSelectorInteraction(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	// Tap 20 Mbps
	bitrate20, err := env.adb.WaitForElement("djiBitrate20", elementTimeout)
	if err != nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		bitrate20, err = env.adb.WaitForElement("djiBitrate20", elementTimeout)
	}
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(bitrate20))
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	require.NotEmpty(t, hierarchy.FindContainingText("20"), "Bitrate tile should show 20 after selecting it")
	screenshot(t, env, "dji_bitrate_selector_interaction")
}

func TestDJI_StreamButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	// Stream button should exist
	streamBtn, err := env.adb.WaitForElement("djiStreamButton", elementTimeout)
	if err != nil {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(300 * time.Millisecond)
		streamBtn, err = env.adb.WaitForElement("djiStreamButton", elementTimeout)
	}
	require.NoError(t, err, "Stream button should exist")
	require.NotNil(t, streamBtn)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	startNodes := hierarchy.FindContainingText("Start Streaming")
	require.NotEmpty(t, startNodes, "Start Streaming button label should be visible")
	screenshot(t, env, "dji_stream_button")
}

func TestDJI_LogSection(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll down to reach the log area
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// The log heading
	logNodes := hierarchy.FindContainingText("Log")
	if len(logNodes) == 0 {
		env.adb.Swipe(500, 600, 500, 100, 300)
		Sleep(500 * time.Millisecond)
		hierarchy, _ = env.adb.DumpUI()
		logNodes = hierarchy.FindContainingText("Log")
	}
	require.NotEmpty(t, logNodes, "Log section heading should be visible")

	// Default log text when no entries
	defaultLog := hierarchy.FindContainingText("No log entries yet")
	require.NotEmpty(t, defaultLog, "Default log text should show 'No log entries yet'")

	screenshot(t, env, "dji_log_section")
}

func TestDJI_LogUpdatesOnActions(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Tap discovery button to generate a log entry
	discoveryBtn, err := env.adb.WaitForElement("djiDiscoveryButton", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(discoveryBtn))
	Sleep(500 * time.Millisecond)

	// Scroll down to see the log
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// The log should now contain the pairing message
	logNodes := hierarchy.FindContainingText("Simulated pairing")
	require.NotEmpty(t, logNodes, "Log should contain 'Simulated pairing' after tapping discovery")
	screenshot(t, env, "dji_log_updates")
}

func TestDJI_WiFiSettingsHeading(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	wifiNodes := hierarchy.FindContainingText("WiFi Settings")
	require.NotEmpty(t, wifiNodes, "WiFi Settings heading should be visible")
	screenshot(t, env, "dji_wifi_settings_heading")
}

func TestDJI_StreamingHeading(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	// Scroll to see Streaming heading
	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	streamingNodes := hierarchy.FindContainingText("Streaming")
	require.NotEmpty(t, streamingNodes, "Streaming heading should be visible")
	screenshot(t, env, "dji_streaming_heading")
}

func TestDJI_StreamSettingsHeading(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "DJI Control")
	Sleep(1 * time.Second)

	env.adb.Swipe(500, 600, 500, 100, 300)
	Sleep(500 * time.Millisecond)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	settingsNodes := hierarchy.FindContainingText("Stream Settings")
	require.NotEmpty(t, settingsNodes, "Stream Settings heading should be visible")
	screenshot(t, env, "dji_stream_settings_heading")
}
