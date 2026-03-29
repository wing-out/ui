package backend

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestMockStreamD_ImplementsInterface(t *testing.T) {
	var _ StreamDBackend = (*MockStreamD)(nil)
}

func TestMockStreamD_DefaultBehavior(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	t.Run("Ping_echoes_payload", func(t *testing.T) {
		resp, err := m.Ping(ctx, "hello")
		require.NoError(t, err)
		require.Equal(t, "hello", resp)
	})

	t.Run("GetConfig_returns_empty_json", func(t *testing.T) {
		cfg, err := m.GetConfig(ctx)
		require.NoError(t, err)
		require.Equal(t, "{}", cfg)
	})

	t.Run("SetConfig_returns_nil", func(t *testing.T) {
		err := m.SetConfig(ctx, "key: value")
		require.NoError(t, err)
	})

	t.Run("SaveConfig_returns_nil", func(t *testing.T) {
		err := m.SaveConfig(ctx)
		require.NoError(t, err)
	})

	t.Run("GetLoggingLevel_returns_5", func(t *testing.T) {
		level, err := m.GetLoggingLevel(ctx)
		require.NoError(t, err)
		require.Equal(t, 5, level)
	})

	t.Run("GetStreamStatus_returns_empty", func(t *testing.T) {
		status, err := m.GetStreamStatus(ctx, StreamIDFullyQualified{PlatformID: "twitch"}, false)
		require.NoError(t, err)
		require.NotNil(t, status)
		require.False(t, status.IsActive)
	})

	t.Run("ListStreamSources_returns_nil", func(t *testing.T) {
		sources, err := m.ListStreamSources(ctx)
		require.NoError(t, err)
		require.Nil(t, sources)
	})

	t.Run("ListStreamForwards_returns_nil", func(t *testing.T) {
		fwds, err := m.ListStreamForwards(ctx)
		require.NoError(t, err)
		require.Nil(t, fwds)
	})

	t.Run("ListProfiles_returns_nil", func(t *testing.T) {
		profiles, err := m.ListProfiles(ctx)
		require.NoError(t, err)
		require.Nil(t, profiles)
	})

	t.Run("GetAccounts_returns_nil", func(t *testing.T) {
		accs, err := m.GetAccounts(ctx, []string{"twitch"})
		require.NoError(t, err)
		require.Nil(t, accs)
	})

	t.Run("PlayerGetLag_returns_zero", func(t *testing.T) {
		lag, err := m.PlayerGetLag(ctx, "player1")
		require.NoError(t, err)
		require.Equal(t, 0.0, lag)
	})
}

func TestMockStreamD_CustomBehavior(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	t.Run("Ping_custom_response", func(t *testing.T) {
		m.PingFunc = func(ctx context.Context, payload string) (string, error) {
			return "pong:" + payload, nil
		}
		resp, err := m.Ping(ctx, "test")
		require.NoError(t, err)
		require.Equal(t, "pong:test", resp)
	})

	t.Run("GetStreamStatus_active", func(t *testing.T) {
		viewers := uint64(1500)
		now := time.Now()
		m.GetStreamStatusFunc = func(ctx context.Context, streamID StreamIDFullyQualified, noCache bool) (*StreamStatus, error) {
			return &StreamStatus{
				IsActive:     true,
				StartedAt:    &now,
				ViewersCount: &viewers,
			}, nil
		}
		status, err := m.GetStreamStatus(ctx, StreamIDFullyQualified{PlatformID: "twitch"}, false)
		require.NoError(t, err)
		require.True(t, status.IsActive)
		require.Equal(t, uint64(1500), *status.ViewersCount)
	})

	t.Run("ListProfiles_returns_profiles", func(t *testing.T) {
		m.ListProfilesFunc = func(ctx context.Context) ([]Profile, error) {
			return []Profile{
				{Name: "1080p", Description: "Full HD"},
				{Name: "720p", Description: "HD"},
			}, nil
		}
		profiles, err := m.ListProfiles(ctx)
		require.NoError(t, err)
		require.Len(t, profiles, 2)
		require.Equal(t, "1080p", profiles[0].Name)
	})

	t.Run("SetConfig_returns_error", func(t *testing.T) {
		expectedErr := errors.New("invalid config")
		m.SetConfigFunc = func(ctx context.Context, configYAML string) error {
			return expectedErr
		}
		err := m.SetConfig(ctx, "bad")
		require.ErrorIs(t, err, expectedErr)
	})

	t.Run("GetAccounts_returns_accounts", func(t *testing.T) {
		m.GetAccountsFunc = func(ctx context.Context, platformIDs []string) ([]Account, error) {
			return []Account{
				{PlatformID: "twitch", AccountID: "123", UserName: "streamer"},
			}, nil
		}
		accs, err := m.GetAccounts(ctx, []string{"twitch"})
		require.NoError(t, err)
		require.Len(t, accs, 1)
		require.Equal(t, "streamer", accs[0].UserName)
	})
}

func TestMockStreamD_CallTracking(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	require.Equal(t, 0, m.CallCount("Ping"))

	_, _ = m.Ping(ctx, "a")
	require.Equal(t, 1, m.CallCount("Ping"))

	_, _ = m.Ping(ctx, "b")
	require.Equal(t, 2, m.CallCount("Ping"))

	_, _ = m.GetConfig(ctx)
	require.Equal(t, 1, m.CallCount("GetConfig"))

	_ = m.SetConfig(ctx, "")
	require.Equal(t, 1, m.CallCount("SetConfig"))

	_ = m.SaveConfig(ctx)
	require.Equal(t, 1, m.CallCount("SaveConfig"))

	_, _ = m.ListStreamForwards(ctx)
	require.Equal(t, 1, m.CallCount("ListStreamForwards"))

	_ = m.SendChatMessage(ctx, "twitch", "123", "hello")
	require.Equal(t, 1, m.CallCount("SendChatMessage"))
}

func TestMockStreamD_SubscribeToChatMessages_CancelsOnContext(t *testing.T) {
	m := NewMockStreamD()
	ctx, cancel := context.WithCancel(context.Background())

	ch, err := m.SubscribeToChatMessages(ctx, 0, 100, "")
	require.NoError(t, err)

	cancel()

	select {
	case _, ok := <-ch:
		require.False(t, ok)
	case <-time.After(time.Second):
		t.Fatal("Chat channel did not close after context cancellation")
	}
}

func TestMockStreamD_SubscribeToChatMessages_Custom(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	m.SubscribeToChatMessagesFunc = func(ctx context.Context, since int64, limit int32, streamID string) (<-chan ChatMessage, error) {
		ch := make(chan ChatMessage, 2)
		ch <- ChatMessage{Platform: "twitch", UserName: "user1", Message: "hello"}
		ch <- ChatMessage{Platform: "youtube", UserName: "user2", Message: "hi"}
		close(ch)
		return ch, nil
	}

	ch, err := m.SubscribeToChatMessages(ctx, 0, 100, "")
	require.NoError(t, err)

	msg1 := <-ch
	require.Equal(t, "twitch", msg1.Platform)
	require.Equal(t, "hello", msg1.Message)

	msg2 := <-ch
	require.Equal(t, "youtube", msg2.Platform)
}

func TestMockStreamD_SubscribeToVariable_CancelsOnContext(t *testing.T) {
	m := NewMockStreamD()
	ctx, cancel := context.WithCancel(context.Background())

	ch, err := m.SubscribeToVariable(ctx, "test_key")
	require.NoError(t, err)

	cancel()

	select {
	case _, ok := <-ch:
		require.False(t, ok)
	case <-time.After(time.Second):
		t.Fatal("Variable channel did not close after context cancellation")
	}
}

func TestMockStreamD_StreamManagement(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	t.Run("AddStreamSource", func(t *testing.T) {
		err := m.AddStreamSource(ctx, "rtmp://test")
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("AddStreamSource"))
	})

	t.Run("RemoveStreamSource", func(t *testing.T) {
		err := m.RemoveStreamSource(ctx, "source1")
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("RemoveStreamSource"))
	})

	t.Run("AddStreamForward", func(t *testing.T) {
		err := m.AddStreamForward(ctx, StreamForward{SourceID: "src", SinkID: "sink"})
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("AddStreamForward"))
	})

	t.Run("RemoveStreamForward", func(t *testing.T) {
		err := m.RemoveStreamForward(ctx, "src", "sink")
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("RemoveStreamForward"))
	})

	t.Run("SetStreamActive", func(t *testing.T) {
		err := m.SetStreamActive(ctx, StreamIDFullyQualified{PlatformID: "twitch"}, true)
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("SetStreamActive"))
	})

	t.Run("ApplyProfile", func(t *testing.T) {
		err := m.ApplyProfile(ctx, StreamIDFullyQualified{PlatformID: "twitch"}, "1080p")
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("ApplyProfile"))
	})
}

func TestMockStreamD_PlayerOperations(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	err := m.PlayerOpen(ctx, "p1", "https://example.com/stream")
	require.NoError(t, err)
	require.Equal(t, 1, m.CallCount("PlayerOpen"))

	err = m.PlayerSetPause(ctx, "p1", true)
	require.NoError(t, err)
	require.Equal(t, 1, m.CallCount("PlayerSetPause"))

	err = m.PlayerClose(ctx, "p1")
	require.NoError(t, err)
	require.Equal(t, 1, m.CallCount("PlayerClose"))
}

func TestMockStreamD_Variables(t *testing.T) {
	m := NewMockStreamD()
	ctx := context.Background()

	t.Run("GetVariable_default_nil", func(t *testing.T) {
		val, err := m.GetVariable(ctx, "key1")
		require.NoError(t, err)
		require.Nil(t, val)
	})

	t.Run("SetVariable", func(t *testing.T) {
		err := m.SetVariable(ctx, "key1", []byte("value1"))
		require.NoError(t, err)
		require.Equal(t, 1, m.CallCount("SetVariable"))
	})

	t.Run("GetVariable_custom", func(t *testing.T) {
		m.GetVariableFunc = func(ctx context.Context, key string) ([]byte, error) {
			if key == "key1" {
				return []byte("value1"), nil
			}
			return nil, errors.New("not found")
		}
		val, err := m.GetVariable(ctx, "key1")
		require.NoError(t, err)
		require.Equal(t, []byte("value1"), val)

		_, err = m.GetVariable(ctx, "key2")
		require.Error(t, err)
	})
}
