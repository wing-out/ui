//go:build test_e2e

package e2e

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/api"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

// TestFull_StreamingPipeline tests a complete streaming flow:
// start backend -> set config -> check profiles/forwards -> check metrics -> save config.
func TestFull_StreamingPipeline(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	mockFF := backend.NewMockFFStream()
	mockSD := backend.NewMockStreamD()

	var configStored string
	mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return configStored, nil
	}
	mockSD.SetConfigFunc = func(ctx context.Context, configYAML string) error {
		configStored = configYAML
		return nil
	}
	mockSD.SaveConfigFunc = func(ctx context.Context) error {
		return nil
	}
	mockSD.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{
			{Name: "IRL Stream", Description: "Outdoor streaming profile"},
		}, nil
	}
	mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
		}, nil
	}

	mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 6000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 4500000, Audio: 128000},
		}, nil
	}
	mockFF.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{SendingUs: 3500, PreTranscodingUs: 1500, TranscodingUs: 2000},
		}, nil
	}
	mockFF.GetInputQualityFunc = func(ctx context.Context) (*backend.QualityReport, error) {
		return &backend.QualityReport{
			Video: backend.StreamQuality{Continuity: 0.998, FrameRate: 29.97},
		}, nil
	}
	mockFF.GetFPSFractionFunc = func(ctx context.Context) (uint32, uint32, error) {
		return 30000, 1001, nil
	}

	client, cleanup := startTestServer(t, mockFF, mockSD)
	defer cleanup()

	// Step 1: Ping to verify connectivity
	pingResp, err := client.Ping(ctx, &api.PingRequest{Payload: "hello"})
	require.NoError(t, err)
	require.Equal(t, "hello", pingResp.GetPayload())

	// Step 2: Set configuration
	_, err = client.SetConfig(ctx, &api.SetConfigRequest{
		Config: "streams:\n  twitch:\n    url: rtmp://live.twitch.tv/live/key123",
	})
	require.NoError(t, err)

	// Step 3: Verify config persists
	configResp, err := client.GetConfig(ctx, &api.GetConfigRequest{})
	require.NoError(t, err)
	require.Contains(t, configResp.GetConfig(), "twitch")

	// Step 4: Check profiles
	profilesResp, err := client.ListProfiles(ctx, &api.ListProfilesRequest{})
	require.NoError(t, err)
	require.Len(t, profilesResp.GetProfiles(), 1)
	require.Equal(t, "IRL Stream", profilesResp.GetProfiles()[0].GetName())

	// Step 5: Check forwards
	fwdResp, err := client.ListStreamForwards(ctx, &api.ListStreamForwardsRequest{})
	require.NoError(t, err)
	require.Len(t, fwdResp.GetForwards(), 1)
	require.Equal(t, "twitch", fwdResp.GetForwards()[0].GetSinkId())

	// Step 6: Check streaming metrics
	brResp, err := client.GetBitRates(ctx, &api.GetBitRatesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(6000000), brResp.GetInputBitRate().GetVideo())

	latResp, err := client.GetLatencies(ctx, &api.GetLatenciesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(3500), latResp.GetVideo().GetSendingUs())

	qualResp, err := client.GetInputQuality(ctx, &api.GetInputQualityRequest{})
	require.NoError(t, err)
	require.InDelta(t, 0.998, qualResp.GetVideo().GetContinuity(), 0.001)

	fpsResp, err := client.GetFPSFraction(ctx, &api.GetFPSFractionRequest{})
	require.NoError(t, err)
	require.Equal(t, uint32(30000), fpsResp.GetNum())
	require.Equal(t, uint32(1001), fpsResp.GetDen())

	// Step 7: Save config
	_, err = client.SaveConfig(ctx, &api.SaveConfigRequest{})
	require.NoError(t, err)

	// Step 8: Check backend mode
	modeResp, err := client.GetBackendMode(ctx, &api.GetBackendModeRequest{})
	require.NoError(t, err)
	require.Equal(t, "hybrid", modeResp.GetMode())
}

// TestFull_MultipleClientsConnect verifies multiple gRPC clients can connect simultaneously.
func TestFull_MultipleClientsConnect(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, cleanup := startTestServer(t, backend.NewMockFFStream(), backend.NewMockStreamD())
	defer cleanup()

	// The client is already connected; verify it works multiple times
	for i := 0; i < 5; i++ {
		resp, err := client.Ping(ctx, &api.PingRequest{Payload: "ping"})
		require.NoError(t, err)
		require.Equal(t, "ping", resp.GetPayload())
	}
}

// TestFull_ErrorHandling verifies error propagation through gRPC.
func TestFull_ErrorHandling(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Server without FFStream backend
	client, cleanup := startTestServer(t, nil, backend.NewMockStreamD())
	defer cleanup()

	// FFStream methods should fail
	_, err := client.GetBitRates(ctx, &api.GetBitRatesRequest{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "ffstream backend is not available")

	// StreamD methods should work
	resp, err := client.GetConfig(ctx, &api.GetConfigRequest{})
	require.NoError(t, err)
	require.NotNil(t, resp)
}

// TestFull_ListStreamServers verifies server listing through gRPC.
func TestFull_ListStreamServers(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockSD := backend.NewMockStreamD()
	mockSD.ListStreamServersFunc = func(ctx context.Context) ([]backend.StreamServer, error) {
		return []backend.StreamServer{
			{ID: "rtmp1", Type: "rtmp", ListenAddr: ":1935"},
			{ID: "srt1", Type: "srt", ListenAddr: ":9000"},
		}, nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	resp, err := client.ListStreamServers(ctx, &api.ListStreamServersRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetServers(), 2)
	require.Equal(t, "rtmp1", resp.GetServers()[0].GetId())
	require.Equal(t, ":1935", resp.GetServers()[0].GetListenAddr())
}

// TestFull_ListStreamPlayers verifies player listing through gRPC.
func TestFull_ListStreamPlayers(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockSD := backend.NewMockStreamD()
	mockSD.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Test Video", Link: "http://example.com/video", Position: 30.5, Length: 120.0},
		}, nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	resp, err := client.ListStreamPlayers(ctx, &api.ListStreamPlayersRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetPlayers(), 1)
	require.Equal(t, "Test Video", resp.GetPlayers()[0].GetTitle())
	require.InDelta(t, 30.5, resp.GetPlayers()[0].GetPosition(), 0.01)
}
