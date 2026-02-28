package backend

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestMockFFStream_ImplementsInterface(t *testing.T) {
	var _ FFStreamBackend = (*MockFFStream)(nil)
}

func TestMockFFStream_DefaultBehavior(t *testing.T) {
	m := NewMockFFStream()
	ctx := context.Background()

	t.Run("Start_returns_nil", func(t *testing.T) {
		err := m.Start(ctx, TranscoderConfig{})
		require.NoError(t, err)
	})

	t.Run("Stop_returns_nil", func(t *testing.T) {
		err := m.Stop(ctx)
		require.NoError(t, err)
	})

	t.Run("GetBitRates_returns_empty", func(t *testing.T) {
		br, err := m.GetBitRates(ctx)
		require.NoError(t, err)
		require.NotNil(t, br)
		require.Equal(t, uint64(0), br.InputBitRate.Video)
	})

	t.Run("GetLatencies_returns_empty", func(t *testing.T) {
		lat, err := m.GetLatencies(ctx)
		require.NoError(t, err)
		require.NotNil(t, lat)
	})

	t.Run("GetFPSFraction_returns_30_1", func(t *testing.T) {
		num, den, err := m.GetFPSFraction(ctx)
		require.NoError(t, err)
		require.Equal(t, uint32(30), num)
		require.Equal(t, uint32(1), den)
	})

	t.Run("GetStats_returns_empty", func(t *testing.T) {
		stats, err := m.GetStats(ctx)
		require.NoError(t, err)
		require.NotNil(t, stats)
	})

	t.Run("GetInputQuality_returns_empty", func(t *testing.T) {
		q, err := m.GetInputQuality(ctx)
		require.NoError(t, err)
		require.NotNil(t, q)
	})

	t.Run("GetOutputQuality_returns_empty", func(t *testing.T) {
		q, err := m.GetOutputQuality(ctx)
		require.NoError(t, err)
		require.NotNil(t, q)
	})

	t.Run("AddInput_returns_nil", func(t *testing.T) {
		err := m.AddInput(ctx, "rtmp://test", 0)
		require.NoError(t, err)
	})

	t.Run("InjectSubtitles_returns_nil", func(t *testing.T) {
		err := m.InjectSubtitles(ctx, []byte("test"), time.Second)
		require.NoError(t, err)
	})

	t.Run("InjectData_returns_nil", func(t *testing.T) {
		err := m.InjectData(ctx, []byte("test"), time.Second)
		require.NoError(t, err)
	})
}

func TestMockFFStream_CustomBehavior(t *testing.T) {
	m := NewMockFFStream()
	ctx := context.Background()

	t.Run("GetBitRates_custom", func(t *testing.T) {
		m.GetBitRatesFunc = func(ctx context.Context) (*BitRates, error) {
			return &BitRates{
				InputBitRate:  BitRateInfo{Video: 5_000_000, Audio: 128_000},
				OutputBitRate: BitRateInfo{Video: 3_000_000, Audio: 128_000},
			}, nil
		}
		br, err := m.GetBitRates(ctx)
		require.NoError(t, err)
		require.Equal(t, uint64(5_000_000), br.InputBitRate.Video)
		require.Equal(t, uint64(3_000_000), br.OutputBitRate.Video)
	})

	t.Run("GetLatencies_custom", func(t *testing.T) {
		m.GetLatenciesFunc = func(ctx context.Context) (*Latencies, error) {
			return &Latencies{
				Video: TrackLatencies{
					PreTranscodingUs: 1000,
					TranscodingUs:    5000,
					SendingUs:        2000,
				},
			}, nil
		}
		lat, err := m.GetLatencies(ctx)
		require.NoError(t, err)
		require.Equal(t, uint64(5000), lat.Video.TranscodingUs)
	})

	t.Run("Start_returns_error", func(t *testing.T) {
		expectedErr := errors.New("pipeline failed")
		m.StartFunc = func(ctx context.Context, cfg TranscoderConfig) error {
			return expectedErr
		}
		err := m.Start(ctx, TranscoderConfig{})
		require.ErrorIs(t, err, expectedErr)
	})

	t.Run("GetFPSFraction_custom", func(t *testing.T) {
		m.GetFPSFractionFunc = func(ctx context.Context) (uint32, uint32, error) {
			return 60, 1, nil
		}
		num, den, err := m.GetFPSFraction(ctx)
		require.NoError(t, err)
		require.Equal(t, uint32(60), num)
		require.Equal(t, uint32(1), den)
	})

	t.Run("Monitor_emits_events", func(t *testing.T) {
		m.MonitorFunc = func(ctx context.Context, req MonitorRequest) (<-chan MonitorEvent, error) {
			ch := make(chan MonitorEvent, 1)
			ch <- MonitorEvent{EventType: "test", Timestamp: 12345}
			close(ch)
			return ch, nil
		}
		ch, err := m.Monitor(ctx, MonitorRequest{})
		require.NoError(t, err)
		ev := <-ch
		require.Equal(t, "test", ev.EventType)
	})
}

func TestMockFFStream_CallTracking(t *testing.T) {
	m := NewMockFFStream()
	ctx := context.Background()

	require.Equal(t, 0, m.CallCount("GetBitRates"))

	_, _ = m.GetBitRates(ctx)
	require.Equal(t, 1, m.CallCount("GetBitRates"))

	_, _ = m.GetBitRates(ctx)
	require.Equal(t, 2, m.CallCount("GetBitRates"))

	_ = m.Start(ctx, TranscoderConfig{})
	require.Equal(t, 1, m.CallCount("Start"))

	_ = m.Stop(ctx)
	require.Equal(t, 1, m.CallCount("Stop"))

	_, _, _ = m.GetFPSFraction(ctx)
	require.Equal(t, 1, m.CallCount("GetFPSFraction"))

	_ = m.SetFPSFraction(ctx, 30, 1)
	require.Equal(t, 1, m.CallCount("SetFPSFraction"))

	_ = m.AddInput(ctx, "rtmp://test", 0)
	require.Equal(t, 1, m.CallCount("AddInput"))

	_ = m.InjectSubtitles(ctx, nil, 0)
	require.Equal(t, 1, m.CallCount("InjectSubtitles"))

	_ = m.SetLoggingLevel(ctx, 5)
	require.Equal(t, 1, m.CallCount("SetLoggingLevel"))
}

func TestMockFFStream_Wait_CancelsOnContext(t *testing.T) {
	m := NewMockFFStream()
	ctx, cancel := context.WithCancel(context.Background())

	done := make(chan struct{})
	go func() {
		_ = m.Wait(ctx)
		close(done)
	}()

	cancel()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Wait did not return after context cancellation")
	}
}

func TestMockFFStream_Monitor_CancelsOnContext(t *testing.T) {
	m := NewMockFFStream()
	ctx, cancel := context.WithCancel(context.Background())

	ch, err := m.Monitor(ctx, MonitorRequest{})
	require.NoError(t, err)

	cancel()

	select {
	case _, ok := <-ch:
		require.False(t, ok)
	case <-time.After(time.Second):
		t.Fatal("Monitor channel did not close after context cancellation")
	}
}
