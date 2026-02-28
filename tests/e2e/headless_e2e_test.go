//go:build test_e2e

package e2e

import (
	"context"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/api"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func startTestServer(t *testing.T, ff backend.FFStreamBackend, sd backend.StreamDBackend) (api.WingOutServiceClient, func()) {
	t.Helper()
	srv := api.NewServer(ff, sd)
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	srvCtx, srvCancel := context.WithCancel(context.Background())
	go func() { _ = srv.Serve(srvCtx, lis) }()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	conn, err := grpcDial(ctx, lis.Addr().String())
	cancel()
	require.NoError(t, err)

	client := api.NewWingOutServiceClient(conn)
	cleanup := func() {
		conn.Close()
		srv.Stop()
		srvCancel()
	}
	return client, cleanup
}

// TestHeadless_BackendStartup verifies the backend starts and accepts gRPC connections.
func TestHeadless_BackendStartup(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, cleanup := startTestServer(t, backend.NewMockFFStream(), backend.NewMockStreamD())
	defer cleanup()

	resp, err := client.Ping(ctx, &api.PingRequest{Payload: "test"})
	require.NoError(t, err)
	require.Equal(t, "test", resp.GetPayload())
}

// TestHeadless_GetBitRates verifies bit rate data flows from mock backend through gRPC.
func TestHeadless_GetBitRates(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockFF := backend.NewMockFFStream()
	mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 5000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 3000000, Audio: 128000},
		}, nil
	}

	client, cleanup := startTestServer(t, mockFF, nil)
	defer cleanup()

	resp, err := client.GetBitRates(ctx, &api.GetBitRatesRequest{})
	require.NoError(t, err)
	require.NotNil(t, resp.GetInputBitRate())
	require.Equal(t, uint64(5000000), resp.GetInputBitRate().GetVideo())
	require.Equal(t, uint64(3000000), resp.GetOutputBitRate().GetVideo())
}

// TestHeadless_GetLatencies verifies latency data flows through gRPC.
func TestHeadless_GetLatencies(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockFF := backend.NewMockFFStream()
	mockFF.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{SendingUs: 5000, PreTranscodingUs: 2000, TranscodingUs: 3000},
		}, nil
	}

	client, cleanup := startTestServer(t, mockFF, nil)
	defer cleanup()

	resp, err := client.GetLatencies(ctx, &api.GetLatenciesRequest{})
	require.NoError(t, err)
	require.NotNil(t, resp.GetVideo())
	require.Equal(t, uint64(5000), resp.GetVideo().GetSendingUs())
	require.Equal(t, uint64(3000), resp.GetVideo().GetTranscodingUs())
}

// TestHeadless_ListProfiles verifies profile listing through gRPC.
func TestHeadless_ListProfiles(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockSD := backend.NewMockStreamD()
	mockSD.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{
			{Name: "720p", Description: "720p 30fps streaming"},
			{Name: "1080p", Description: "1080p 60fps high quality"},
		}, nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	resp, err := client.ListProfiles(ctx, &api.ListProfilesRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetProfiles(), 2)
	require.Equal(t, "720p", resp.GetProfiles()[0].GetName())
	require.Equal(t, "1080p", resp.GetProfiles()[1].GetName())
}

// TestHeadless_GetConfig verifies config retrieval through gRPC.
func TestHeadless_GetConfig(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockSD := backend.NewMockStreamD()
	mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return "streams:\n  - name: main\n    url: rtmp://localhost/live", nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	resp, err := client.GetConfig(ctx, &api.GetConfigRequest{})
	require.NoError(t, err)
	require.Contains(t, resp.GetConfig(), "streams:")
}

// TestHeadless_SetAndGetConfig verifies config round-trip through gRPC.
func TestHeadless_SetAndGetConfig(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	var storedConfig string
	mockSD := backend.NewMockStreamD()
	mockSD.GetConfigFunc = func(ctx context.Context) (string, error) {
		return storedConfig, nil
	}
	mockSD.SetConfigFunc = func(ctx context.Context, configYAML string) error {
		storedConfig = configYAML
		return nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	// Set config
	_, err := client.SetConfig(ctx, &api.SetConfigRequest{Config: "test: updated"})
	require.NoError(t, err)

	// Get config and verify round-trip
	resp, err := client.GetConfig(ctx, &api.GetConfigRequest{})
	require.NoError(t, err)
	require.Equal(t, "test: updated", resp.GetConfig())
}

// TestHeadless_ListStreamForwards verifies forward listing through gRPC.
func TestHeadless_ListStreamForwards(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockSD := backend.NewMockStreamD()
	mockSD.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
			{SourceID: "cam0", SinkID: "youtube", SinkType: "rtmp", Enabled: false},
		}, nil
	}

	client, cleanup := startTestServer(t, nil, mockSD)
	defer cleanup()

	resp, err := client.ListStreamForwards(ctx, &api.ListStreamForwardsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetForwards(), 2)
	require.Equal(t, "twitch", resp.GetForwards()[0].GetSinkId())
	require.True(t, resp.GetForwards()[0].GetEnabled())
	require.False(t, resp.GetForwards()[1].GetEnabled())
}

// TestHeadless_GetInputQuality verifies quality metrics through gRPC.
func TestHeadless_GetInputQuality(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	mockFF := backend.NewMockFFStream()
	mockFF.GetInputQualityFunc = func(ctx context.Context) (*backend.QualityReport, error) {
		return &backend.QualityReport{
			Video: backend.StreamQuality{Continuity: 0.998, FrameRate: 29.97},
		}, nil
	}

	client, cleanup := startTestServer(t, mockFF, nil)
	defer cleanup()

	resp, err := client.GetInputQuality(ctx, &api.GetInputQualityRequest{})
	require.NoError(t, err)
	require.InDelta(t, 0.998, resp.GetVideo().GetContinuity(), 0.001)
	require.InDelta(t, 29.97, resp.GetVideo().GetFrameRate(), 0.01)
}
