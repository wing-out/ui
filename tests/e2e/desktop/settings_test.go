//go:build desktop_e2e

package desktop

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestDesktop_SettingsStructure(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")

	node, err := env.atspi.WaitForElement("settingsPage", elementTimeout)
	require.NoError(t, err)
	require.NotNil(t, node)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Connection"), "Connection section should be visible")
	require.NotEmpty(t, tree.FindContainingText("Configuration"), "Configuration section should be visible")
	screenshot(t, env, "settings_structure")
}

func TestDesktop_ConfigEditor(t *testing.T) {
	env := sharedEnv

	// Set mock config
	env.mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return "server:\n  port: 8080", nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	configNodes := tree.FindContainingText("port: 8080")
	require.NotEmpty(t, configNodes, "config editor should show 'port: 8080' from backend")

	// Verify config action buttons exist
	for _, btn := range []string{"configApplyButton", "configSaveButton", "configReloadButton"} {
		node := tree.FindByName(btn)
		require.NotNil(t, node, "button %q should exist", btn)
	}
	screenshot(t, env, "config_editor")

	// Restore default
	var storedConfig = "# default config"
	env.mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return storedConfig, nil
	}
}

func TestDesktop_OAuthSection(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	oauthField := tree.FindByName("oauthCodeField")
	require.NotNil(t, oauthField, "OAuth code field should exist")

	submitBtn := tree.FindByName("submitOAuthButton")
	require.NotNil(t, submitBtn, "Submit OAuth button should exist")
	screenshot(t, env, "oauth_section")
}

func TestDesktop_SystemSection(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	resetCacheBtn := tree.FindByName("resetCacheButton")
	require.NotNil(t, resetCacheBtn, "Reset cache button should exist")

	restartBtn := tree.FindByName("restartButton")
	require.NotNil(t, restartBtn, "Restart button should exist")
	screenshot(t, env, "system_section")
}

func TestDesktop_SettingsModeToggle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")

	modes := []string{"settingsModeEmbedded", "settingsModeRemote", "settingsModeHybrid"}
	for _, mode := range modes {
		t.Run(mode, func(t *testing.T) {
			err := env.atspi.ActivateByName(mode)
			require.NoError(t, err, "mode button %q should be clickable", mode)
			Sleep(300 * time.Millisecond)
			screenshot(t, env, "settings_"+mode)
		})
	}
}

func TestDesktop_ApplyCallsSetConfig(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("configApplyButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SetConfig"), 1, "Apply should call SetConfig")
}

func TestDesktop_SaveCallsSaveConfig(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("configSaveButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SaveConfig"), 1, "Save should call SaveConfig")
}

func TestDesktop_ReloadRefreshesConfig(t *testing.T) {
	env := sharedEnv

	var configValue = "old: config"
	env.mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return configValue, nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(2 * time.Second)

	// Change mock
	configValue = "new: reloaded_config"

	// Tap Reload
	require.NoError(t, env.atspi.ActivateByName("configReloadButton"))
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)
	nodes := tree.FindContainingText("reloaded_config")
	require.NotEmpty(t, nodes, "config editor should show reloaded config")
	screenshot(t, env, "config_reloaded")

	// Restore
	env.mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return "# default config", nil
	}
}

func TestDesktop_OAuthSubmitCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	// Type OAuth code
	require.NoError(t, env.atspi.ActivateByName("oauthCodeField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("test-oauth-code"))
	Sleep(300 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap submit
	require.NoError(t, env.atspi.ActivateByName("submitOAuthButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SubmitOAuthCode"), 1,
		"SubmitOAuthCode should have been called after submitting OAuth code")
	screenshot(t, env, "settings_oauth_submit_backend")
}

func TestDesktop_RestartCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("restartButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("Restart"), 1,
		"Restart should have been called after tapping restart button")
	screenshot(t, env, "settings_restart_backend")
}

func TestDesktop_LoggingLevelButtons(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	levels := []string{"loggingLevel0", "loggingLevel1", "loggingLevel2", "loggingLevel3", "loggingLevel4", "loggingLevel5"}
	for _, level := range levels {
		t.Run(level, func(t *testing.T) {
			node := tree.FindByName(level)
			require.NotNil(t, node, "logging level button %q should exist", level)
		})
	}
	screenshot(t, env, "settings_logging_levels")
}

func TestDesktop_LoggingLevelChangeCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()

	// Tap logging level 5
	require.NoError(t, env.atspi.ActivateByName("loggingLevel5"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("SetLoggingLevel"), 1,
		"SetLoggingLevel should have been called after changing logging level")
	screenshot(t, env, "settings_logging_level_change")
}

func TestDesktop_ModeButtonLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Embedded"), "'Embedded' mode button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Remote"), "'Remote' mode button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Hybrid"), "'Hybrid' mode button label should be visible")
	screenshot(t, env, "settings_mode_labels")
}

func TestDesktop_BackendHostLabel(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	hostNodes := tree.FindContainingText("Backend Host")
	require.NotEmpty(t, hostNodes, "'Backend Host' label should be visible in settings")
	screenshot(t, env, "settings_backend_host_label")
}

func TestDesktop_ConfigButtonLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Apply"), "'Apply' button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Save"), "'Save' button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Reload"), "'Reload' button label should be visible")
	screenshot(t, env, "settings_config_button_labels")
}

func TestDesktop_SystemButtonLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Reset Cache"), "'Reset Cache' button label should be visible")
	require.NotEmpty(t, tree.FindContainingText("Restart"), "'Restart' button label should be visible")
	screenshot(t, env, "settings_system_button_labels")
}

func TestDesktop_AppSettingsLabels(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// App Settings section
	appNodes := tree.FindContainingText("App Settings")
	require.NotEmpty(t, appNodes, "'App Settings' section heading should be visible")

	// Preview RTMP URL/Port fields
	previewUrlField := tree.FindByName("previewRtmpUrlField")
	require.NotNil(t, previewUrlField, "Preview RTMP URL field should exist")

	previewPortField := tree.FindByName("previewRtmpPortField")
	require.NotNil(t, previewPortField, "Preview RTMP Port field should exist")

	// Manual Input FPS field
	manualFpsField := tree.FindByName("manualInputFpsField")
	require.NotNil(t, manualFpsField, "Manual Input FPS field should exist")
	screenshot(t, env, "settings_app_settings")
}

func TestDesktop_ResetCacheCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Settings")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("resetCacheButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ResetCache"), 1,
		"ResetCache should have been called after tapping Reset Cache button")
	screenshot(t, env, "settings_reset_cache_backend")
}
