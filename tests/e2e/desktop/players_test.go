//go:build desktop_e2e

package desktop

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDesktop_PlayersList(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Background Music"), "player title should be visible")
	require.NotEmpty(t, tree.FindContainingText("example.com"), "player link should be visible")
	// Position: 65s = 1:05, Length: 240s = 4:00
	require.NotEmpty(t, tree.FindContainingText("1:05"), "player position should show 1:05")
	require.NotEmpty(t, tree.FindContainingText("4:00"), "player length should show 4:00")
	screenshot(t, env, "players_data")
}

func TestDesktop_PlayerControls(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Player control buttons should exist
	playPauseBtn := tree.FindByName("playerPlayPauseBtn")
	require.NotNil(t, playPauseBtn, "play/pause button should be visible")

	stopBtn := tree.FindByName("playerStopBtn")
	require.NotNil(t, stopBtn, "stop button should be visible")

	closeBtn := tree.FindByName("playerCloseBtn")
	require.NotNil(t, closeBtn, "close button should be visible")
	screenshot(t, env, "player_controls")
}

func TestDesktop_PlayersEmptyState(t *testing.T) {
	env := sharedEnv

	origFunc := env.mockSD.ListStreamPlayersFunc
	env.mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{}, nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	emptyNodes := tree.FindContainingText("No active players")
	require.NotEmpty(t, emptyNodes, "empty state message should be visible")
	screenshot(t, env, "players_empty")

	// Restore
	env.mockSD.ListStreamPlayersFunc = origFunc
}

func TestDesktop_PlayersDynamicUpdate(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
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
	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Sound Effects"), "second player should appear")
	screenshot(t, env, "players_dynamic_update")

	// Restore
	env.mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Background Music", Link: "http://example.com/music.mp3", Position: 65.0, Length: 240.0},
		}, nil
	}
}

func TestDesktop_PlayersPollingFrequency(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	env.mockSD.ResetCallCounts()
	time.Sleep(5 * time.Second)

	count := env.mockSD.CallCount("ListStreamPlayers")
	require.GreaterOrEqual(t, count, 2, "ListStreamPlayers should be polled at least 2 times in 5s, got %d", count)
	t.Logf("ListStreamPlayers called %d times in 5s", count)
}

func TestDesktop_PlayerOpenButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	urlInput := tree.FindByName("playerUrlInput")
	require.NotNil(t, urlInput, "player URL input should be visible")

	openBtn := tree.FindByName("playerOpenBtn")
	require.NotNil(t, openBtn, "player Open button should be visible")
	screenshot(t, env, "player_open_controls")
}

func TestDesktop_PlayersPageTitle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	require.NotEmpty(t, tree.FindContainingText("Stream Players"), "'Stream Players' title should be visible")
	screenshot(t, env, "players_title")
}

func TestDesktop_PlayPauseCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("playerPlayPauseBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerSetPause"), 1,
		"PlayerSetPause should have been called after tapping play/pause")
	screenshot(t, env, "players_play_pause_backend")
}

func TestDesktop_PlayerStopCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("playerStopBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerStop"), 1,
		"PlayerStop should have been called after tapping stop")
	screenshot(t, env, "players_stop_backend")
}

func TestDesktop_PlayerCloseCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	env.mockSD.ResetCallCounts()

	require.NoError(t, env.atspi.ActivateByName("playerCloseBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerClose"), 1,
		"PlayerClose should have been called after tapping close")
	screenshot(t, env, "players_close_backend")
}

func TestDesktop_PlayerOpenURLCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(2 * time.Second)

	// Type URL in input field
	require.NoError(t, env.atspi.ActivateByName("playerUrlInput"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("http://test.mp3"))
	Sleep(300 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap Open button
	require.NoError(t, env.atspi.ActivateByName("playerOpenBtn"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("PlayerOpen"), 1,
		"PlayerOpen should have been called after tapping Open")
	screenshot(t, env, "players_open_url_backend")
}

func TestDesktop_PlayerOpenURLSection(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Players")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	openUrlNodes := tree.FindContainingText("Open URL")
	require.NotEmpty(t, openUrlNodes, "'Open URL' heading should be visible")
	screenshot(t, env, "players_open_url_section")
}
