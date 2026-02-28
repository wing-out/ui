//go:build android_e2e

package android

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestPlayers_ShowsMockData(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("Background Music"), "player title should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("example.com"), "player link should be visible")
	// Position: 65s = 1:05, Length: 240s = 4:00
	require.NotEmpty(t, hierarchy.FindContainingText("1:05"), "player position should show 1:05")
	require.NotEmpty(t, hierarchy.FindContainingText("4:00"), "player length should show 4:00")
	screenshot(t, env, "players_data")
}

func TestPlayers_PageTitle(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("Stream Players"), "Stream Players title should be visible")
	screenshot(t, env, "players_title")
}

func TestPlayers_EmptyState(t *testing.T) {
	env := sharedEnv

	origFunc := env.mockSD.ListStreamPlayersFunc
	env.mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	emptyNodes := hierarchy.FindContainingText("No active players")
	require.NotEmpty(t, emptyNodes, "empty state message should be visible")
	screenshot(t, env, "players_empty")

	// Restore
	env.mockSD.ListStreamPlayersFunc = origFunc
}

func TestPlayers_PollingFrequency(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()
	time.Sleep(5 * time.Second)

	count := env.mockSD.CallCount("ListStreamPlayers")
	require.GreaterOrEqual(t, count, 2, "ListStreamPlayers should be polled at least 2 times in 5s, got %d", count)
	t.Logf("ListStreamPlayers called %d times in 5s", count)
}

func TestPlayers_DynamicUpdate(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	// Add a second player mid-test
	env.mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Background Music", Link: "http://example.com/music.mp3", Position: 65.0, Length: 240.0},
			{ID: "p2", Title: "Sound Effects", Link: "http://example.com/sfx.mp3", Position: 10.0, Length: 30.0},
		}, nil
	}

	Sleep(3 * time.Second)
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("Sound Effects"), "second player should appear")
	screenshot(t, env, "players_dynamic_update")

	// Restore
	env.mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Background Music", Link: "http://example.com/music.mp3", Position: 65.0, Length: 240.0},
		}, nil
	}
}

func TestPlayers_PlayPauseButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	playPauseButtons := hierarchy.FindAllByContentDesc("playerPlayPauseBtn")
	require.NotEmpty(t, playPauseButtons, "Play/Pause button should exist for the player")
	screenshot(t, env, "players_play_pause")
}

func TestPlayers_PlayPauseCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	playPauseButtons := hierarchy.FindAllByContentDesc("playerPlayPauseBtn")
	require.NotEmpty(t, playPauseButtons, "Play/Pause button should exist")
	require.NoError(t, env.adb.TapNode(playPauseButtons[0]))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerSetPause"), 1, "PlayerSetPause should have been called")
	screenshot(t, env, "players_play_pause_backend")
}

func TestPlayers_StopButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	stopButtons := hierarchy.FindAllByContentDesc("playerStopBtn")
	require.NotEmpty(t, stopButtons, "Stop button should exist for the player")
	screenshot(t, env, "players_stop")
}

func TestPlayers_CloseButton(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	closeButtons := hierarchy.FindAllByContentDesc("playerCloseBtn")
	require.NotEmpty(t, closeButtons, "Close button should exist for the player")
	screenshot(t, env, "players_close")
}

func TestPlayers_CloseCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	closeButtons := hierarchy.FindAllByContentDesc("playerCloseBtn")
	require.NotEmpty(t, closeButtons, "Close button should exist")
	require.NoError(t, env.adb.TapNode(closeButtons[0]))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerClose"), 1, "PlayerClose should have been called")
	screenshot(t, env, "players_close_backend")
}

func TestPlayers_OpenURLSection(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// "Open URL" heading
	openUrlNodes := hierarchy.FindContainingText("Open URL")
	require.NotEmpty(t, openUrlNodes, "Open URL heading should be visible")

	// URL input field
	urlInput := hierarchy.FindByContentDesc("playerUrlInput")
	require.NotNil(t, urlInput, "Player URL input field should exist")

	// Open button
	openBtn := hierarchy.FindByContentDesc("playerOpenBtn")
	require.NotNil(t, openBtn, "Player Open button should exist")

	screenshot(t, env, "players_open_url_section")
}

func TestPlayers_OpenURLCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	// Type URL
	urlInput, err := env.adb.WaitForElement("playerUrlInput", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(urlInput))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.adb.TypeText("http://test.mp3"))
	Sleep(300 * time.Millisecond)

	// Dismiss keyboard so Open button is accessible
	require.NoError(t, env.adb.PressBack())
	Sleep(500 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap Open
	openBtn, err := env.adb.WaitForElement("playerOpenBtn", elementTimeout)
	require.NoError(t, err)
	require.NoError(t, env.adb.TapNode(openBtn))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerOpen"), 1, "PlayerOpen should have been called")
	screenshot(t, env, "players_open_url_backend")
}

func TestPlayers_ControlCallsBackend(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	// Tap the Stop button
	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)
	stopButtons := hierarchy.FindAllByContentDesc("playerStopBtn")
	require.NotEmpty(t, stopButtons, "Stop button should exist")
	require.NoError(t, env.adb.TapNode(stopButtons[0]))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerStop"), 1, "PlayerStop should have been called")
	screenshot(t, env, "players_control_backend")
}
