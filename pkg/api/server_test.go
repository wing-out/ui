package api

import (
	"context"
	"encoding/json"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// testServer starts a gRPC server with mock backends and returns a connected client.
func testServer(t *testing.T, ff backend.FFStreamBackend, sd backend.StreamDBackend) (WingOutServiceClient, func()) {
	return testServerWithAVD(t, ff, sd, nil)
}

// testServerWithAVD starts a gRPC server with all three mock backends and returns a connected client.
func testServerWithAVD(t *testing.T, ff backend.FFStreamBackend, sd backend.StreamDBackend, avd backend.AVDBackend) (WingOutServiceClient, func()) {
	t.Helper()

	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	srv := NewServer(ff, sd, avd)
	ctx, cancel := context.WithCancel(context.Background())

	go func() {
		_ = srv.Serve(ctx, lis)
	}()

	// Wait briefly for server to start
	time.Sleep(50 * time.Millisecond)

	conn, err := grpc.NewClient(
		lis.Addr().String(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	require.NoError(t, err)

	client := NewWingOutServiceClient(conn)
	cleanup := func() {
		conn.Close()
		cancel()
	}
	return client, cleanup
}

func TestServer_NewServer(t *testing.T) {
	ff := backend.NewMockFFStream()
	sd := backend.NewMockStreamD()
	srv := NewServer(ff, sd, nil)

	require.NotNil(t, srv)
	require.Equal(t, ff, srv.FFStream())
	require.Equal(t, sd, srv.StreamD())
}

func TestServer_NewServer_NilBackends(t *testing.T) {
	srv := NewServer(nil, nil, nil)
	require.NotNil(t, srv)
	require.Nil(t, srv.FFStream())
	require.Nil(t, srv.StreamD())
}

func TestServer_WriteHandshake(t *testing.T) {
	srv := NewServer(nil, nil, nil)
	var output []byte
	err := srv.WriteHandshake("127.0.0.1:5000", func(data []byte) {
		output = data
	})
	require.NoError(t, err)
	require.NotEmpty(t, output)

	var info HandshakeInfo
	err = json.Unmarshal(output[:len(output)-1], &info) // strip newline
	require.NoError(t, err)
	require.Equal(t, "127.0.0.1:5000", info.GRPCAddr)
	require.Equal(t, "2.0.0", info.Version)
}

func TestServer_DoubleServe_Fails(t *testing.T) {
	lis1, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer lis1.Close()

	lis2, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	defer lis2.Close()

	srv := NewServer(nil, nil, nil)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = srv.Serve(ctx, lis1) }()
	time.Sleep(50 * time.Millisecond)

	err = srv.Serve(ctx, lis2)
	require.Error(t, err)
	require.Contains(t, err.Error(), "already started")
}

func TestService_Ping_WithStreamD(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PingFunc = func(ctx context.Context, payload string) (string, error) {
		return "echo:" + payload, nil
	}
	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.Ping(context.Background(), &PingRequest{Payload: "hello"})
	require.NoError(t, err)
	require.Equal(t, "echo:hello", resp.GetPayload())
}

func TestService_Ping_WithoutStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.Ping(context.Background(), &PingRequest{Payload: "test"})
	require.Error(t, err)
	require.Contains(t, err.Error(), "streamd backend is not available")
}

func TestService_GetBitRates(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 5_000_000, Audio: 128_000},
			OutputBitRate: backend.BitRateInfo{Video: 3_000_000, Audio: 128_000},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetBitRates(context.Background(), &GetBitRatesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(5_000_000), resp.GetInputBitRate().GetVideo())
	require.Equal(t, uint64(3_000_000), resp.GetOutputBitRate().GetVideo())
	require.Equal(t, uint64(128_000), resp.GetInputBitRate().GetAudio())
}

func TestService_GetBitRates_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetBitRates(context.Background(), &GetBitRatesRequest{})
	require.Error(t, err)
}

func TestService_GetLatencies(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{
				PreTranscodingUs: 1000,
				TranscodingUs:    5000,
				SendingUs:        2000,
			},
			Audio: backend.TrackLatencies{
				PreTranscodingUs: 500,
			},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetLatencies(context.Background(), &GetLatenciesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(5000), resp.GetVideo().GetTranscodingUs())
	require.Equal(t, uint64(2000), resp.GetVideo().GetSendingUs())
	require.Equal(t, uint64(500), resp.GetAudio().GetPreTranscodingUs())
}

func TestService_GetInputQuality(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetInputQualityFunc = func(ctx context.Context) (*backend.QualityReport, error) {
		return &backend.QualityReport{
			Video: backend.StreamQuality{
				Continuity: 0.99,
				FrameRate:  29.97,
			},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetInputQuality(context.Background(), &GetInputQualityRequest{})
	require.NoError(t, err)
	require.InDelta(t, 0.99, resp.GetVideo().GetContinuity(), 0.001)
	require.InDelta(t, 29.97, resp.GetVideo().GetFrameRate(), 0.01)
}

func TestService_GetOutputQuality(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetOutputQualityFunc = func(ctx context.Context) (*backend.QualityReport, error) {
		return &backend.QualityReport{
			Video: backend.StreamQuality{FrameRate: 30.0},
			Audio: backend.StreamQuality{Continuity: 1.0},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetOutputQuality(context.Background(), &GetOutputQualityRequest{})
	require.NoError(t, err)
	require.InDelta(t, 30.0, resp.GetVideo().GetFrameRate(), 0.01)
	require.InDelta(t, 1.0, resp.GetAudio().GetContinuity(), 0.01)
}

func TestService_GetFPSFraction(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetFPSFractionFunc = func(ctx context.Context) (uint32, uint32, error) {
		return 60, 1, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetFPSFraction(context.Background(), &GetFPSFractionRequest{})
	require.NoError(t, err)
	require.Equal(t, uint32(60), resp.GetNum())
	require.Equal(t, uint32(1), resp.GetDen())
}

func TestService_SetFPSFraction(t *testing.T) {
	ff := backend.NewMockFFStream()
	var setNum, setDen uint32
	ff.SetFPSFractionFunc = func(ctx context.Context, num, den uint32) error {
		setNum = num
		setDen = den
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetFPSFraction(context.Background(), &SetFPSFractionRequest{Num: 24, Den: 1})
	require.NoError(t, err)
	require.Equal(t, uint32(24), setNum)
	require.Equal(t, uint32(1), setDen)
}

func TestService_GetStats(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetStatsFunc = func(ctx context.Context) (*backend.Stats, error) {
		return &backend.Stats{
			NodeCounters: backend.NodeCounters{
				ReceivedPackets:  1000,
				SentPackets:      950,
				ProcessedFrames:  500,
			},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetStats(context.Background(), &GetStatsRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(1000), resp.GetReceivedPackets())
	require.Equal(t, uint64(950), resp.GetSentPackets())
	require.Equal(t, uint64(500), resp.GetProcessedFrames())
}

func TestService_InjectSubtitles(t *testing.T) {
	ff := backend.NewMockFFStream()
	var injectedData []byte
	var injectedDur time.Duration
	ff.InjectSubtitlesFunc = func(ctx context.Context, data []byte, dur time.Duration) error {
		injectedData = data
		injectedDur = dur
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.InjectSubtitles(context.Background(), &InjectSubtitlesRequest{
		Data:       []byte("test subtitle"),
		DurationNs: uint64(5 * time.Second),
	})
	require.NoError(t, err)
	require.Equal(t, []byte("test subtitle"), injectedData)
	require.Equal(t, 5*time.Second, injectedDur)
}

func TestService_InjectData(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.InjectDataFunc = func(ctx context.Context, data []byte, dur time.Duration) error {
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.InjectData(context.Background(), &InjectDataRequest{
		Data:       []byte("binary data"),
		DurationNs: uint64(time.Second),
	})
	require.NoError(t, err)
}

func TestService_GetConfig(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetConfigFunc = func(ctx context.Context) (string, error) {
		return "server:\n  port: 8080", nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetConfig(context.Background(), &GetConfigRequest{})
	require.NoError(t, err)
	require.Contains(t, resp.GetConfig(), "port: 8080")
}

func TestService_SetConfig(t *testing.T) {
	sd := backend.NewMockStreamD()
	var savedConfig string
	sd.SetConfigFunc = func(ctx context.Context, configYAML string) error {
		savedConfig = configYAML
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetConfig(context.Background(), &SetConfigRequest{Config: "new: config"})
	require.NoError(t, err)
	require.Equal(t, "new: config", savedConfig)
}

func TestService_SaveConfig(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SaveConfig(context.Background(), &SaveConfigRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("SaveConfig"))
}

func TestService_GetStreamStatus(t *testing.T) {
	sd := backend.NewMockStreamD()
	viewers := uint64(1234)
	now := time.Now()
	sd.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		require.Equal(t, "twitch", streamID.PlatformID)
		return &backend.StreamStatus{
			IsActive:     true,
			StartedAt:    &now,
			ViewersCount: &viewers,
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetStreamStatus(context.Background(), &GetStreamStatusRequest{
		PlatformId: "twitch",
		AccountId:  "acc1",
		StreamId:   "s1",
	})
	require.NoError(t, err)
	require.True(t, resp.GetIsActive())
	require.NotNil(t, resp.ViewersCount)
	require.Equal(t, uint64(1234), *resp.ViewersCount)
}

func TestService_ListStreamForwards(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam1", SinkID: "twitch", SinkType: "platform", Enabled: true},
			{SourceID: "cam1", SinkID: "youtube", SinkType: "platform", Enabled: false},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListStreamForwards(context.Background(), &ListStreamForwardsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetForwards(), 2)
	require.Equal(t, "cam1", resp.GetForwards()[0].GetSourceId())
	require.True(t, resp.GetForwards()[0].GetEnabled())
	require.False(t, resp.GetForwards()[1].GetEnabled())
}

func TestService_ListStreamServers(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListStreamServersFunc = func(ctx context.Context) ([]backend.StreamServer, error) {
		return []backend.StreamServer{
			{ID: "srv1", Type: "rtmp", ListenAddr: ":1935"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListStreamServers(context.Background(), &ListStreamServersRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetServers(), 1)
	require.Equal(t, "rtmp", resp.GetServers()[0].GetType())
}

func TestService_ListStreamPlayers(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Test", Link: "https://stream.test", Position: 10.5, Length: 60.0},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListStreamPlayers(context.Background(), &ListStreamPlayersRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetPlayers(), 1)
	require.Equal(t, "Test", resp.GetPlayers()[0].GetTitle())
	require.InDelta(t, 10.5, resp.GetPlayers()[0].GetPosition(), 0.01)
}

func TestService_ListProfiles(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{
			{Name: "1080p60", Description: "Full HD 60fps"},
			{Name: "720p30", Description: "HD 30fps"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListProfiles(context.Background(), &ListProfilesRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetProfiles(), 2)
	require.Equal(t, "1080p60", resp.GetProfiles()[0].GetName())
	require.Equal(t, "Full HD 60fps", resp.GetProfiles()[0].GetDescription())
}

func TestService_GetBackendMode(t *testing.T) {
	t.Run("both_backends", func(t *testing.T) {
		client, cleanup := testServer(t, backend.NewMockFFStream(), backend.NewMockStreamD())
		defer cleanup()

		resp, err := client.GetBackendMode(context.Background(), &GetBackendModeRequest{})
		require.NoError(t, err)
		require.Equal(t, "hybrid", resp.GetMode())
	})

	t.Run("ffstream_only", func(t *testing.T) {
		client, cleanup := testServer(t, backend.NewMockFFStream(), nil)
		defer cleanup()

		resp, err := client.GetBackendMode(context.Background(), &GetBackendModeRequest{})
		require.NoError(t, err)
		require.Equal(t, "ffstream_only", resp.GetMode())
	})

	t.Run("streamd_only", func(t *testing.T) {
		client, cleanup := testServer(t, nil, backend.NewMockStreamD())
		defer cleanup()

		resp, err := client.GetBackendMode(context.Background(), &GetBackendModeRequest{})
		require.NoError(t, err)
		require.Equal(t, "streamd_only", resp.GetMode())
	})

	t.Run("no_backends", func(t *testing.T) {
		client, cleanup := testServer(t, nil, nil)
		defer cleanup()

		resp, err := client.GetBackendMode(context.Background(), &GetBackendModeRequest{})
		require.NoError(t, err)
		require.Equal(t, "unknown", resp.GetMode())
	})
}

func TestService_SubscribeToChatMessages(t *testing.T) {
	sd := backend.NewMockStreamD()
	ts := time.Now().Unix()
	sd.SubscribeToChatMessagesFunc = func(ctx context.Context, since int64, limit int32, streamID string) (<-chan backend.ChatMessage, error) {
		ch := make(chan backend.ChatMessage, 3)
		ch <- backend.ChatMessage{ID: "1", Platform: "twitch", UserName: "user1", Message: "hello", Timestamp: ts}
		ch <- backend.ChatMessage{ID: "2", Platform: "youtube", UserName: "user2", Message: "hi", Timestamp: ts + 60}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToChatMessages(context.Background(), &SubscribeToChatMessagesRequest{
		SinceUnixNano: 0,
		Limit:         100,
	})
	require.NoError(t, err)

	msg1, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "twitch", msg1.GetPlatform())
	require.Equal(t, "hello", msg1.GetMessage())
	require.Equal(t, ts, msg1.GetTimestamp(), "chat message timestamp must be propagated")

	msg2, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "youtube", msg2.GetPlatform())
	require.Equal(t, ts+60, msg2.GetTimestamp(), "chat message timestamp must be propagated")
}

// --- StreamD: Logging ---

func TestService_SetLoggingLevel(t *testing.T) {
	sd := backend.NewMockStreamD()
	var setLevel int
	sd.SetLoggingLevelFunc = func(ctx context.Context, level int) error {
		setLevel = level
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetLoggingLevel(context.Background(), &SetLoggingLevelRequest{Level: 3})
	require.NoError(t, err)
	require.Equal(t, 3, setLevel)
}

func TestService_SetLoggingLevel_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetLoggingLevel(context.Background(), &SetLoggingLevelRequest{Level: 3})
	require.Error(t, err)
}

func TestService_GetLoggingLevel(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetLoggingLevelFunc = func(ctx context.Context) (int, error) {
		return 3, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetLoggingLevel(context.Background(), &GetLoggingLevelRequest{})
	require.NoError(t, err)
	require.Equal(t, LoggingLevel(3), resp.GetLevel())
}

func TestService_GetLoggingLevel_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetLoggingLevel(context.Background(), &GetLoggingLevelRequest{})
	require.Error(t, err)
}

// --- StreamD: Cache ---

func TestService_ResetCache(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.ResetCache(context.Background(), &ResetCacheRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("ResetCache"))
}

func TestService_ResetCache_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ResetCache(context.Background(), &ResetCacheRequest{})
	require.Error(t, err)
}

func TestService_InitCache(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.InitCache(context.Background(), &InitCacheRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("InitCache"))
}

func TestService_InitCache_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.InitCache(context.Background(), &InitCacheRequest{})
	require.Error(t, err)
}

// --- StreamD: Stream Lifecycle ---

func TestService_SetStreamActive(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotStreamID backend.StreamIDFullyQualified
	var gotActive bool
	sd.SetStreamActiveFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, active bool) error {
		gotStreamID = streamID
		gotActive = active
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetStreamActive(context.Background(), &SetStreamActiveRequest{
		StreamId: &StreamIDFullyQualifiedProto{
			PlatformId: "twitch",
			AccountId:  "acc1",
			StreamId:   "s1",
		},
		Active: true,
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotStreamID.PlatformID)
	require.Equal(t, "acc1", gotStreamID.AccountID)
	require.Equal(t, "s1", gotStreamID.StreamID)
	require.True(t, gotActive)
}

func TestService_SetStreamActive_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetStreamActive(context.Background(), &SetStreamActiveRequest{Active: true})
	require.Error(t, err)
}

func TestService_GetStreams(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetStreamsFunc = func(ctx context.Context) ([]backend.Stream, error) {
		return []backend.Stream{
			{ID: backend.StreamIDFullyQualified{PlatformID: "twitch", AccountID: "a1", StreamID: "s1"}, IsActive: true, Title: "Stream 1"},
			{ID: backend.StreamIDFullyQualified{PlatformID: "youtube", AccountID: "a2", StreamID: "s2"}, IsActive: false, Title: "Stream 2"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetStreams(context.Background(), &GetStreamsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetStreams(), 2)
	require.Equal(t, "twitch", resp.GetStreams()[0].GetId().GetPlatformId())
	require.True(t, resp.GetStreams()[0].GetIsActive())
	require.Equal(t, "Stream 1", resp.GetStreams()[0].GetTitle())
	require.Equal(t, "youtube", resp.GetStreams()[1].GetId().GetPlatformId())
	require.False(t, resp.GetStreams()[1].GetIsActive())
}

func TestService_GetStreams_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetStreams(context.Background(), &GetStreamsRequest{})
	require.Error(t, err)
}

func TestService_CreateStream(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatformID, gotTitle, gotDescription, gotProfile string
	sd.CreateStreamFunc = func(ctx context.Context, platformID string, title string, description string, profile string) error {
		gotPlatformID = platformID
		gotTitle = title
		gotDescription = description
		gotProfile = profile
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.CreateStream(context.Background(), &CreateStreamRequest{
		PlatformId:  "twitch",
		Title:       "My Stream",
		Description: "A test stream",
		Profile:     "1080p60",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatformID)
	require.Equal(t, "My Stream", gotTitle)
	require.Equal(t, "A test stream", gotDescription)
	require.Equal(t, "1080p60", gotProfile)
}

func TestService_CreateStream_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.CreateStream(context.Background(), &CreateStreamRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

func TestService_DeleteStream(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotStreamID backend.StreamIDFullyQualified
	sd.DeleteStreamFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified) error {
		gotStreamID = streamID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.DeleteStream(context.Background(), &DeleteStreamRequest{
		StreamId: &StreamIDFullyQualifiedProto{
			PlatformId: "twitch",
			AccountId:  "acc1",
			StreamId:   "s1",
		},
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotStreamID.PlatformID)
	require.Equal(t, "s1", gotStreamID.StreamID)
}

func TestService_DeleteStream_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.DeleteStream(context.Background(), &DeleteStreamRequest{})
	require.Error(t, err)
}

func TestService_GetActiveStreamIDs(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetActiveStreamIDsFunc = func(ctx context.Context) ([]backend.StreamIDFullyQualified, error) {
		return []backend.StreamIDFullyQualified{
			{PlatformID: "twitch", AccountID: "a1", StreamID: "s1"},
			{PlatformID: "youtube", AccountID: "a2", StreamID: "s2"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetActiveStreamIDs(context.Background(), &GetActiveStreamIDsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetStreamIds(), 2)
	require.Equal(t, "twitch", resp.GetStreamIds()[0].GetPlatformId())
	require.Equal(t, "youtube", resp.GetStreamIds()[1].GetPlatformId())
}

func TestService_GetActiveStreamIDs_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetActiveStreamIDs(context.Background(), &GetActiveStreamIDsRequest{})
	require.Error(t, err)
}

func TestService_StartStream(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotProfileName string
	sd.StartStreamFunc = func(ctx context.Context, platID string, profileName string) error {
		gotPlatID = platID
		gotProfileName = profileName
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StartStream(context.Background(), &StartStreamRequest{
		PlatformId:  "twitch",
		ProfileName: "1080p60",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "1080p60", gotProfileName)
}

func TestService_StartStream_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StartStream(context.Background(), &StartStreamRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

func TestService_EndStream(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID string
	sd.EndStreamFunc = func(ctx context.Context, platID string) error {
		gotPlatID = platID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.EndStream(context.Background(), &EndStreamRequest{
		PlatformId: "twitch",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
}

func TestService_EndStream_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.EndStream(context.Background(), &EndStreamRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

// --- StreamD: Accounts & Platforms ---

func TestService_GetAccounts(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetAccountsFunc = func(ctx context.Context, platformIDs []string) ([]backend.Account, error) {
		return []backend.Account{
			{PlatformID: "twitch", AccountID: "acc1", UserName: "user1"},
			{PlatformID: "youtube", AccountID: "acc2", UserName: "user2"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetAccounts(context.Background(), &GetAccountsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetAccounts(), 2)
	require.Equal(t, "twitch", resp.GetAccounts()[0].GetPlatformId())
	require.Equal(t, "acc1", resp.GetAccounts()[0].GetAccountId())
}

func TestService_GetAccounts_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetAccounts(context.Background(), &GetAccountsRequest{})
	require.Error(t, err)
}

func TestService_IsBackendEnabled(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.IsBackendEnabledFunc = func(ctx context.Context, platformID string) (bool, error) {
		return true, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.IsBackendEnabled(context.Background(), &IsBackendEnabledRequest{PlatformId: "twitch"})
	require.NoError(t, err)
	require.True(t, resp.GetEnabled())
}

func TestService_IsBackendEnabled_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.IsBackendEnabled(context.Background(), &IsBackendEnabledRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

func TestService_GetBackendInfo(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetBackendInfoFunc = func(ctx context.Context, platformID string) (*backend.BackendInfo, error) {
		return &backend.BackendInfo{
			PlatformID:   "twitch",
			Capabilities: []string{"chat", "stream"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetBackendInfo(context.Background(), &GetBackendInfoRequest{PlatformId: "twitch"})
	require.NoError(t, err)
	require.Equal(t, "twitch", resp.GetPlatformId())
}

func TestService_GetBackendInfo_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetBackendInfo(context.Background(), &GetBackendInfoRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

func TestService_GetPlatforms(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetPlatformsFunc = func(ctx context.Context) ([]string, error) {
		return []string{"twitch", "youtube"}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetPlatforms(context.Background(), &GetPlatformsRequest{})
	require.NoError(t, err)
	require.Equal(t, []string{"twitch", "youtube"}, resp.GetPlatformIds())
}

func TestService_GetPlatforms_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetPlatforms(context.Background(), &GetPlatformsRequest{})
	require.Error(t, err)
}

// --- StreamD: Metadata ---

func TestService_SetTitle(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotTitle string
	sd.SetTitleFunc = func(ctx context.Context, platID string, title string) error {
		gotPlatID = platID
		gotTitle = title
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetTitle(context.Background(), &SetTitleRequest{
		PlatformId: "twitch",
		Title:      "New Title",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "New Title", gotTitle)
}

func TestService_SetTitle_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetTitle(context.Background(), &SetTitleRequest{PlatformId: "twitch", Title: "t"})
	require.Error(t, err)
}

func TestService_SetDescription(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotDescription string
	sd.SetDescriptionFunc = func(ctx context.Context, platID string, description string) error {
		gotPlatID = platID
		gotDescription = description
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetDescription(context.Background(), &SetDescriptionRequest{
		PlatformId:  "twitch",
		Description: "New Description",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "New Description", gotDescription)
}

func TestService_SetDescription_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetDescription(context.Background(), &SetDescriptionRequest{PlatformId: "twitch"})
	require.Error(t, err)
}

// --- StreamD: Profiles ---

func TestService_ApplyProfile(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotProfileName string
	sd.ApplyProfileFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, profileName string) error {
		gotProfileName = profileName
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.ApplyProfile(context.Background(), &ApplyProfileRequest{
		ProfileName: "1080p60",
	})
	require.NoError(t, err)
	require.Equal(t, "1080p60", gotProfileName)
}

func TestService_ApplyProfile_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ApplyProfile(context.Background(), &ApplyProfileRequest{ProfileName: "1080p60"})
	require.Error(t, err)
}

// --- StreamD: Variables ---

func TestService_GetVariable(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetVariableFunc = func(ctx context.Context, key string) ([]byte, error) {
		require.Equal(t, "my_key", key)
		return []byte("my_value"), nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetVariable(context.Background(), &GetVariableRequest{Key: "my_key"})
	require.NoError(t, err)
	require.Equal(t, []byte("my_value"), resp.GetValue())
}

func TestService_GetVariable_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetVariable(context.Background(), &GetVariableRequest{Key: "k"})
	require.Error(t, err)
}

func TestService_GetVariableHash(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetVariableHashFunc = func(ctx context.Context, key string, hashType string) (string, error) {
		require.Equal(t, "my_key", key)
		return "abc123hash", nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetVariableHash(context.Background(), &GetVariableHashRequest{
		Key:      "my_key",
		HashType: HashType_HASH_SHA1,
	})
	require.NoError(t, err)
	require.Equal(t, "abc123hash", resp.GetHash())
}

func TestService_GetVariableHash_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetVariableHash(context.Background(), &GetVariableHashRequest{Key: "k"})
	require.Error(t, err)
}

func TestService_SetVariable(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotKey string
	var gotValue []byte
	sd.SetVariableFunc = func(ctx context.Context, key string, value []byte) error {
		gotKey = key
		gotValue = value
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SetVariable(context.Background(), &SetVariableRequest{
		Key:   "my_key",
		Value: []byte("my_value"),
	})
	require.NoError(t, err)
	require.Equal(t, "my_key", gotKey)
	require.Equal(t, []byte("my_value"), gotValue)
}

func TestService_SetVariable_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetVariable(context.Background(), &SetVariableRequest{Key: "k", Value: []byte("v")})
	require.Error(t, err)
}

// --- StreamD: OAuth ---

func TestService_SubmitOAuthCode(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotRequestID, gotCode string
	sd.SubmitOAuthCodeFunc = func(ctx context.Context, requestID string, code string) error {
		gotRequestID = requestID
		gotCode = code
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SubmitOAuthCode(context.Background(), &SubmitOAuthCodeRequest{
		RequestId: "req-123",
		Code:      "auth-code-456",
	})
	require.NoError(t, err)
	require.Equal(t, "req-123", gotRequestID)
	require.Equal(t, "auth-code-456", gotCode)
}

func TestService_SubmitOAuthCode_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SubmitOAuthCode(context.Background(), &SubmitOAuthCodeRequest{RequestId: "r", Code: "c"})
	require.Error(t, err)
}

// --- StreamD: Stream Servers ---

func TestService_StartStreamServer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotConfig backend.StreamServer
	sd.StartStreamServerFunc = func(ctx context.Context, config backend.StreamServer) error {
		gotConfig = config
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StartStreamServer(context.Background(), &StartStreamServerRequest{
		ServerType: StreamServerType_STREAM_SERVER_TYPE_RTMP,
		ListenAddr: ":1935",
	})
	require.NoError(t, err)
	require.Equal(t, "STREAM_SERVER_TYPE_RTMP", gotConfig.Type)
	require.Equal(t, ":1935", gotConfig.ListenAddr)
}

func TestService_StartStreamServer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StartStreamServer(context.Background(), &StartStreamServerRequest{ListenAddr: ":1935"})
	require.Error(t, err)
}

func TestService_StopStreamServer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotServerID string
	sd.StopStreamServerFunc = func(ctx context.Context, serverID string) error {
		gotServerID = serverID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StopStreamServer(context.Background(), &StopStreamServerRequest{
		ServerId: "srv-123",
	})
	require.NoError(t, err)
	require.Equal(t, "srv-123", gotServerID)
}

func TestService_StopStreamServer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StopStreamServer(context.Background(), &StopStreamServerRequest{ServerId: "srv-1"})
	require.Error(t, err)
}

// --- StreamD: Stream Sources ---

func TestService_ListStreamSources(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{
			{ID: "src1", URL: "rtmp://localhost/live", IsActive: true, IsSuppressed: false},
			{ID: "src2", URL: "srt://localhost:9000", IsActive: false, IsSuppressed: true},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListStreamSources(context.Background(), &ListStreamSourcesRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetSources(), 2)
	require.Equal(t, "src1", resp.GetSources()[0].GetId())
	require.Equal(t, "rtmp://localhost/live", resp.GetSources()[0].GetUrl())
	require.True(t, resp.GetSources()[0].GetIsActive())
	require.Equal(t, "src2", resp.GetSources()[1].GetId())
	require.False(t, resp.GetSources()[1].GetIsActive())
}

func TestService_ListStreamSources_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ListStreamSources(context.Background(), &ListStreamSourcesRequest{})
	require.Error(t, err)
}

func TestService_AddStreamSource(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotURL string
	sd.AddStreamSourceFunc = func(ctx context.Context, url string) error {
		gotURL = url
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddStreamSource(context.Background(), &AddStreamSourceRequest{
		Url: "rtmp://newhost/live",
	})
	require.NoError(t, err)
	require.Equal(t, "rtmp://newhost/live", gotURL)
}

func TestService_AddStreamSource_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddStreamSource(context.Background(), &AddStreamSourceRequest{Url: "rtmp://test"})
	require.Error(t, err)
}

func TestService_RemoveStreamSource(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotID string
	sd.RemoveStreamSourceFunc = func(ctx context.Context, id string) error {
		gotID = id
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveStreamSource(context.Background(), &RemoveStreamSourceRequest{
		SourceId: "src-123",
	})
	require.NoError(t, err)
	require.Equal(t, "src-123", gotID)
}

func TestService_RemoveStreamSource_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveStreamSource(context.Background(), &RemoveStreamSourceRequest{SourceId: "s"})
	require.Error(t, err)
}

// --- StreamD: Stream Sinks ---

func TestService_ListStreamSinks(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListStreamSinksFunc = func(ctx context.Context) ([]backend.StreamSink, error) {
		return []backend.StreamSink{
			{ID: "sink1", Type: "custom", URL: "rtmp://out1"},
			{ID: "sink2", Type: "platform", URL: "rtmp://out2"},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListStreamSinks(context.Background(), &ListStreamSinksRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetSinks(), 2)
	require.Equal(t, "sink1", resp.GetSinks()[0].GetId())
	require.Equal(t, "rtmp://out1", resp.GetSinks()[0].GetUrl())
}

func TestService_ListStreamSinks_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ListStreamSinks(context.Background(), &ListStreamSinksRequest{})
	require.Error(t, err)
}

func TestService_AddStreamSink(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotSink backend.StreamSink
	sd.AddStreamSinkFunc = func(ctx context.Context, sink backend.StreamSink) error {
		gotSink = sink
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddStreamSink(context.Background(), &AddStreamSinkRequest{
		SinkId: "sink-new",
		Url:    "rtmp://example.com/live",
	})
	require.NoError(t, err)
	require.Equal(t, "sink-new", gotSink.ID)
	require.Equal(t, "rtmp://example.com/live", gotSink.URL)
}

func TestService_AddStreamSink_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddStreamSink(context.Background(), &AddStreamSinkRequest{SinkId: "s"})
	require.Error(t, err)
}

func TestService_UpdateStreamSink(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotSink backend.StreamSink
	sd.UpdateStreamSinkFunc = func(ctx context.Context, sink backend.StreamSink) error {
		gotSink = sink
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.UpdateStreamSink(context.Background(), &UpdateStreamSinkRequest{
		SinkId: "sink-1",
		Url:    "rtmp://updated.com/live",
		EncoderConfig: &EncoderConfigProto{
			VideoBitrate: 5000000,
			AudioBitrate: 128000,
		},
	})
	require.NoError(t, err)
	require.Equal(t, "sink-1", gotSink.ID)
	require.Equal(t, "rtmp://updated.com/live", gotSink.URL)
	require.NotNil(t, gotSink.EncoderConfig)
	require.Equal(t, uint64(5000000), gotSink.EncoderConfig.VideoBitrate)
	require.Equal(t, uint64(128000), gotSink.EncoderConfig.AudioBitrate)
}

func TestService_UpdateStreamSink_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.UpdateStreamSink(context.Background(), &UpdateStreamSinkRequest{SinkId: "s"})
	require.Error(t, err)
}

func TestService_GetStreamSinkConfig(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetStreamSinkConfigFunc = func(ctx context.Context, sinkID string) (*backend.StreamSinkConfig, error) {
		require.Equal(t, "sink-1", sinkID)
		return &backend.StreamSinkConfig{
			URL: "rtmp://example.com/live",
			EncoderConfig: &backend.EncoderConfig{
				VideoBitrate: 3000000,
			},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetStreamSinkConfig(context.Background(), &GetStreamSinkConfigRequest{SinkId: "sink-1"})
	require.NoError(t, err)
	require.Equal(t, "rtmp://example.com/live", resp.GetConfig().GetUrl())
	require.Equal(t, uint64(3000000), resp.GetConfig().GetEncoder().GetVideoBitrate())
}

func TestService_GetStreamSinkConfig_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetStreamSinkConfig(context.Background(), &GetStreamSinkConfigRequest{SinkId: "s"})
	require.Error(t, err)
}

func TestService_RemoveStreamSink(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotID string
	sd.RemoveStreamSinkFunc = func(ctx context.Context, id string) error {
		gotID = id
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveStreamSink(context.Background(), &RemoveStreamSinkRequest{SinkId: "sink-del"})
	require.NoError(t, err)
	require.Equal(t, "sink-del", gotID)
}

func TestService_RemoveStreamSink_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveStreamSink(context.Background(), &RemoveStreamSinkRequest{SinkId: "s"})
	require.Error(t, err)
}

// --- StreamD: Stream Forwards ---

func TestService_AddStreamForward(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotFwd backend.StreamForward
	sd.AddStreamForwardFunc = func(ctx context.Context, fwd backend.StreamForward) error {
		gotFwd = fwd
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddStreamForward(context.Background(), &AddStreamForwardRequest{
		SourceId: "cam1",
		SinkId:   "twitch-sink",
		Enabled:  true,
		Quirks: &StreamForwardQuirksProto{
			RestartOnError:                 true,
			PlatformRecognitionWaitSeconds: 5,
		},
	})
	require.NoError(t, err)
	require.Equal(t, "cam1", gotFwd.SourceID)
	require.Equal(t, "twitch-sink", gotFwd.SinkID)
	require.True(t, gotFwd.Enabled)
	require.NotNil(t, gotFwd.Quirks)
	require.True(t, gotFwd.Quirks.RestartOnError)
	require.Equal(t, uint32(5), gotFwd.Quirks.PlatformRecognitionWaitSeconds)
}

func TestService_AddStreamForward_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddStreamForward(context.Background(), &AddStreamForwardRequest{SourceId: "s", SinkId: "d"})
	require.Error(t, err)
}

func TestService_UpdateStreamForward(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotFwd backend.StreamForward
	sd.UpdateStreamForwardFunc = func(ctx context.Context, fwd backend.StreamForward) error {
		gotFwd = fwd
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.UpdateStreamForward(context.Background(), &UpdateStreamForwardRequest{
		SourceId: "cam1",
		SinkId:   "twitch-sink",
		Enabled:  false,
	})
	require.NoError(t, err)
	require.Equal(t, "cam1", gotFwd.SourceID)
	require.Equal(t, "twitch-sink", gotFwd.SinkID)
	require.False(t, gotFwd.Enabled)
}

func TestService_UpdateStreamForward_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.UpdateStreamForward(context.Background(), &UpdateStreamForwardRequest{SourceId: "s"})
	require.Error(t, err)
}

func TestService_RemoveStreamForward(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotSourceID, gotSinkID string
	sd.RemoveStreamForwardFunc = func(ctx context.Context, sourceID, sinkID string) error {
		gotSourceID = sourceID
		gotSinkID = sinkID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveStreamForward(context.Background(), &RemoveStreamForwardRequest{
		SourceId: "cam1",
		SinkId:   "twitch-sink",
	})
	require.NoError(t, err)
	require.Equal(t, "cam1", gotSourceID)
	require.Equal(t, "twitch-sink", gotSinkID)
}

func TestService_RemoveStreamForward_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveStreamForward(context.Background(), &RemoveStreamForwardRequest{SourceId: "s", SinkId: "d"})
	require.Error(t, err)
}

// --- StreamD: Stream Publisher ---

func TestService_WaitForStreamPublisher(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.WaitForStreamPublisherFunc = func(ctx context.Context, sourceID string) error {
		require.Equal(t, "src-1", sourceID)
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.WaitForStreamPublisher(context.Background(), &WaitForStreamPublisherRequest{
		SourceId: "src-1",
	})
	require.NoError(t, err)
}

func TestService_WaitForStreamPublisher_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.WaitForStreamPublisher(context.Background(), &WaitForStreamPublisherRequest{SourceId: "s"})
	require.Error(t, err)
}

// --- StreamD: Player CRUD ---

func TestService_AddStreamPlayer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayer backend.StreamPlayer
	sd.AddStreamPlayerFunc = func(ctx context.Context, player backend.StreamPlayer) error {
		gotPlayer = player
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddStreamPlayer(context.Background(), &AddStreamPlayerRequest{
		Player: &StreamPlayerProto{
			Id:    "player-1",
			Title: "Main Player",
			Link:  "https://stream.test/live",
		},
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayer.ID)
	require.Equal(t, "Main Player", gotPlayer.Title)
	require.Equal(t, "https://stream.test/live", gotPlayer.Link)
}

func TestService_AddStreamPlayer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddStreamPlayer(context.Background(), &AddStreamPlayerRequest{
		Player: &StreamPlayerProto{Id: "p1"},
	})
	require.Error(t, err)
}

func TestService_RemoveStreamPlayer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayerID string
	sd.RemoveStreamPlayerFunc = func(ctx context.Context, playerID string) error {
		gotPlayerID = playerID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveStreamPlayer(context.Background(), &RemoveStreamPlayerRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayerID)
}

func TestService_RemoveStreamPlayer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveStreamPlayer(context.Background(), &RemoveStreamPlayerRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_UpdateStreamPlayer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayer backend.StreamPlayer
	sd.UpdateStreamPlayerFunc = func(ctx context.Context, player backend.StreamPlayer) error {
		gotPlayer = player
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.UpdateStreamPlayer(context.Background(), &UpdateStreamPlayerRequest{
		Player: &StreamPlayerProto{
			Id:       "player-1",
			Title:    "Updated Player",
			IsPaused: true,
		},
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayer.ID)
	require.Equal(t, "Updated Player", gotPlayer.Title)
	require.True(t, gotPlayer.IsPaused)
}

func TestService_UpdateStreamPlayer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.UpdateStreamPlayer(context.Background(), &UpdateStreamPlayerRequest{
		Player: &StreamPlayerProto{Id: "p"},
	})
	require.Error(t, err)
}

func TestService_GetStreamPlayer(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetStreamPlayerFunc = func(ctx context.Context, playerID string) (*backend.StreamPlayer, error) {
		require.Equal(t, "player-1", playerID)
		return &backend.StreamPlayer{
			ID:       "player-1",
			Title:    "My Player",
			Link:     "https://stream.test/vid",
			Position: 30.5,
			Length:   120.0,
			IsPaused: false,
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetStreamPlayer(context.Background(), &GetStreamPlayerRequest{PlayerId: "player-1"})
	require.NoError(t, err)
	require.Equal(t, "player-1", resp.GetPlayer().GetId())
	require.Equal(t, "My Player", resp.GetPlayer().GetTitle())
	require.Equal(t, "https://stream.test/vid", resp.GetPlayer().GetLink())
	require.InDelta(t, 30.5, resp.GetPlayer().GetPosition(), 0.01)
	require.InDelta(t, 120.0, resp.GetPlayer().GetLength(), 0.01)
	require.False(t, resp.GetPlayer().GetIsPaused())
}

func TestService_GetStreamPlayer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetStreamPlayer(context.Background(), &GetStreamPlayerRequest{PlayerId: "p"})
	require.Error(t, err)
}

// --- StreamD: Player Control ---

func TestService_StreamPlayerOpen(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayerID, gotURL string
	sd.PlayerOpenFunc = func(ctx context.Context, playerID string, url string) error {
		gotPlayerID = playerID
		gotURL = url
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerOpen(context.Background(), &StreamPlayerOpenRequest{
		PlayerId: "player-1",
		Url:      "https://stream.test/video.mp4",
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayerID)
	require.Equal(t, "https://stream.test/video.mp4", gotURL)
}

func TestService_StreamPlayerOpen_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerOpen(context.Background(), &StreamPlayerOpenRequest{PlayerId: "p", Url: "u"})
	require.Error(t, err)
}

func TestService_StreamPlayerProcessTitle(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerProcessTitleFunc = func(ctx context.Context, playerID string, title string) (string, error) {
		require.Equal(t, "player-1", playerID)
		require.Equal(t, "raw title", title)
		return "processed title", nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerProcessTitle(context.Background(), &StreamPlayerProcessTitleRequest{
		PlayerId: "player-1",
		Title:    "raw title",
	})
	require.NoError(t, err)
}

func TestService_StreamPlayerProcessTitle_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerProcessTitle(context.Background(), &StreamPlayerProcessTitleRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerGetLink(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerGetLinkFunc = func(ctx context.Context, playerID string) (string, error) {
		require.Equal(t, "player-1", playerID)
		return "https://stream.test/current", nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerGetLink(context.Background(), &StreamPlayerGetLinkRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.Equal(t, "https://stream.test/current", resp.GetUrl())
}

func TestService_StreamPlayerGetLink_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerGetLink(context.Background(), &StreamPlayerGetLinkRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerIsEnded(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerIsEndedFunc = func(ctx context.Context, playerID string) (bool, error) {
		require.Equal(t, "player-1", playerID)
		return true, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerIsEnded(context.Background(), &StreamPlayerIsEndedRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.True(t, resp.GetIsEnded())
}

func TestService_StreamPlayerIsEnded_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerIsEnded(context.Background(), &StreamPlayerIsEndedRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerGetPosition(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerGetPositionFunc = func(ctx context.Context, playerID string) (float64, error) {
		require.Equal(t, "player-1", playerID)
		return 45.5, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerGetPosition(context.Background(), &StreamPlayerGetPositionRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.InDelta(t, 45.5, resp.GetSeconds(), 0.01)
}

func TestService_StreamPlayerGetPosition_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerGetPosition(context.Background(), &StreamPlayerGetPositionRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerGetLength(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerGetLengthFunc = func(ctx context.Context, playerID string) (float64, error) {
		require.Equal(t, "player-1", playerID)
		return 120.0, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerGetLength(context.Background(), &StreamPlayerGetLengthRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.InDelta(t, 120.0, resp.GetSeconds(), 0.01)
}

func TestService_StreamPlayerGetLength_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerGetLength(context.Background(), &StreamPlayerGetLengthRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerGetLag(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerGetLagFunc = func(ctx context.Context, playerID string) (float64, error) {
		require.Equal(t, "player-1", playerID)
		return 2.5, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerGetLag(context.Background(), &StreamPlayerGetLagRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.InDelta(t, 2.5, resp.GetSeconds(), 0.01)
}

func TestService_StreamPlayerGetLag_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerGetLag(context.Background(), &StreamPlayerGetLagRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerSetSpeed(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayerID string
	var gotSpeed float64
	sd.PlayerSetSpeedFunc = func(ctx context.Context, playerID string, speed float64) error {
		gotPlayerID = playerID
		gotSpeed = speed
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerSetSpeed(context.Background(), &StreamPlayerSetSpeedRequest{
		PlayerId: "player-1",
		Speed:    1.5,
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayerID)
	require.InDelta(t, 1.5, gotSpeed, 0.01)
}

func TestService_StreamPlayerSetSpeed_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerSetSpeed(context.Background(), &StreamPlayerSetSpeedRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerGetSpeed(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerGetSpeedFunc = func(ctx context.Context, playerID string) (float64, error) {
		require.Equal(t, "player-1", playerID)
		return 1.5, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.StreamPlayerGetSpeed(context.Background(), &StreamPlayerGetSpeedRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.InDelta(t, 1.5, resp.GetSpeed(), 0.01)
}

func TestService_StreamPlayerGetSpeed_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerGetSpeed(context.Background(), &StreamPlayerGetSpeedRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerSetPause(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlayerID string
	var gotPaused bool
	sd.PlayerSetPauseFunc = func(ctx context.Context, playerID string, paused bool) error {
		gotPlayerID = playerID
		gotPaused = paused
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerSetPause(context.Background(), &StreamPlayerSetPauseRequest{
		PlayerId: "player-1",
		Paused:   true,
	})
	require.NoError(t, err)
	require.Equal(t, "player-1", gotPlayerID)
	require.True(t, gotPaused)
}

func TestService_StreamPlayerSetPause_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerSetPause(context.Background(), &StreamPlayerSetPauseRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerStop(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerStop(context.Background(), &StreamPlayerStopRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("PlayerStop"))
}

func TestService_StreamPlayerStop_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerStop(context.Background(), &StreamPlayerStopRequest{PlayerId: "p"})
	require.Error(t, err)
}

func TestService_StreamPlayerClose(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.StreamPlayerClose(context.Background(), &StreamPlayerCloseRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("PlayerClose"))
}

func TestService_StreamPlayerClose_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.StreamPlayerClose(context.Background(), &StreamPlayerCloseRequest{PlayerId: "p"})
	require.Error(t, err)
}

// --- StreamD: Timers ---

func TestService_AddTimer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotTimer backend.Timer
	sd.AddTimerFunc = func(ctx context.Context, timer backend.Timer) error {
		gotTimer = timer
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddTimer(context.Background(), &AddTimerRequest{
		Timer: &TimerProto{
			Id:              "timer-1",
			IntervalSeconds: 60,
			Action: &ActionProto{
				Type:   "send_message",
				Params: map[string]string{"msg": "hello"},
			},
		},
	})
	require.NoError(t, err)
	require.Equal(t, "timer-1", gotTimer.ID)
	require.Equal(t, uint32(60), gotTimer.IntervalSeconds)
	require.Equal(t, "send_message", gotTimer.Action.Type)
	require.Equal(t, "hello", gotTimer.Action.Params["msg"])
}

func TestService_AddTimer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddTimer(context.Background(), &AddTimerRequest{Timer: &TimerProto{Id: "t"}})
	require.Error(t, err)
}

func TestService_RemoveTimer(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotTimerID string
	sd.RemoveTimerFunc = func(ctx context.Context, timerID string) error {
		gotTimerID = timerID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveTimer(context.Background(), &RemoveTimerRequest{TimerId: "timer-1"})
	require.NoError(t, err)
	require.Equal(t, "timer-1", gotTimerID)
}

func TestService_RemoveTimer_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveTimer(context.Background(), &RemoveTimerRequest{TimerId: "t"})
	require.Error(t, err)
}

func TestService_ListTimers(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListTimersFunc = func(ctx context.Context) ([]backend.Timer, error) {
		return []backend.Timer{
			{ID: "timer-1", IntervalSeconds: 30, Action: backend.Action{Type: "notify"}},
			{ID: "timer-2", IntervalSeconds: 60, Action: backend.Action{Type: "refresh"}},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListTimers(context.Background(), &ListTimersRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetTimers(), 2)
	require.Equal(t, "timer-1", resp.GetTimers()[0].GetId())
	require.Equal(t, uint32(30), resp.GetTimers()[0].GetIntervalSeconds())
	require.Equal(t, "notify", resp.GetTimers()[0].GetAction().GetType())
	require.Equal(t, "timer-2", resp.GetTimers()[1].GetId())
}

func TestService_ListTimers_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ListTimers(context.Background(), &ListTimersRequest{})
	require.Error(t, err)
}

// --- StreamD: Trigger Rules ---

func TestService_ListTriggerRules(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.ListTriggerRulesFunc = func(ctx context.Context) ([]backend.TriggerRule, error) {
		return []backend.TriggerRule{
			{ID: "rule-1", EventQuery: backend.EventQuery{EventType: "chat", Filter: "user=bot"}, Action: backend.Action{Type: "reply"}, Enabled: true},
			{ID: "rule-2", EventQuery: backend.EventQuery{EventType: "follow"}, Action: backend.Action{Type: "shoutout"}, Enabled: false},
		}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.ListTriggerRules(context.Background(), &ListTriggerRulesRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetRules(), 2)
	require.Equal(t, "rule-1", resp.GetRules()[0].GetId())
	require.True(t, resp.GetRules()[0].GetEnabled())
	require.Equal(t, "reply", resp.GetRules()[0].GetAction().GetType())
	require.Equal(t, "rule-2", resp.GetRules()[1].GetId())
	require.False(t, resp.GetRules()[1].GetEnabled())
}

func TestService_ListTriggerRules_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.ListTriggerRules(context.Background(), &ListTriggerRulesRequest{})
	require.Error(t, err)
}

func TestService_AddTriggerRule(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotRule backend.TriggerRule
	sd.AddTriggerRuleFunc = func(ctx context.Context, rule backend.TriggerRule) error {
		gotRule = rule
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.AddTriggerRule(context.Background(), &AddTriggerRuleRequest{
		Rule: &TriggerRuleProto{
			Id: "rule-new",
			EventQuery: &EventQueryProto{
				Filter: "user=admin",
			},
			Action: &ActionProto{
				Type:   "ban",
				Params: map[string]string{"reason": "spam"},
			},
			Enabled: true,
		},
	})
	require.NoError(t, err)
	require.Equal(t, "rule-new", gotRule.ID)
	require.Equal(t, "user=admin", gotRule.EventQuery.Filter)
	require.Equal(t, "ban", gotRule.Action.Type)
	require.Equal(t, "spam", gotRule.Action.Params["reason"])
	require.True(t, gotRule.Enabled)
}

func TestService_AddTriggerRule_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AddTriggerRule(context.Background(), &AddTriggerRuleRequest{Rule: &TriggerRuleProto{Id: "r"}})
	require.Error(t, err)
}

func TestService_RemoveTriggerRule(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotRuleID string
	sd.RemoveTriggerRuleFunc = func(ctx context.Context, ruleID string) error {
		gotRuleID = ruleID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveTriggerRule(context.Background(), &RemoveTriggerRuleRequest{RuleId: "rule-1"})
	require.NoError(t, err)
	require.Equal(t, "rule-1", gotRuleID)
}

func TestService_RemoveTriggerRule_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveTriggerRule(context.Background(), &RemoveTriggerRuleRequest{RuleId: "r"})
	require.Error(t, err)
}

func TestService_UpdateTriggerRule(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotRule backend.TriggerRule
	sd.UpdateTriggerRuleFunc = func(ctx context.Context, rule backend.TriggerRule) error {
		gotRule = rule
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.UpdateTriggerRule(context.Background(), &UpdateTriggerRuleRequest{
		Rule: &TriggerRuleProto{
			Id:      "rule-1",
			Enabled: false,
			Action: &ActionProto{
				Type: "updated_action",
			},
		},
	})
	require.NoError(t, err)
	require.Equal(t, "rule-1", gotRule.ID)
	require.False(t, gotRule.Enabled)
	require.Equal(t, "updated_action", gotRule.Action.Type)
}

func TestService_UpdateTriggerRule_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.UpdateTriggerRule(context.Background(), &UpdateTriggerRuleRequest{Rule: &TriggerRuleProto{Id: "r"}})
	require.Error(t, err)
}

// --- StreamD: Events ---

func TestService_SubmitEvent(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotEvent backend.Event
	sd.SubmitEventFunc = func(ctx context.Context, event backend.Event) error {
		gotEvent = event
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SubmitEvent(context.Background(), &SubmitEventRequest{
		Event: &EventProto{
			Type: EventType_EVENT_TYPE_WINDOW_FOCUS_CHANGE,
			Data: []byte("window-data"),
		},
	})
	require.NoError(t, err)
	require.Equal(t, "EVENT_TYPE_WINDOW_FOCUS_CHANGE", gotEvent.Type)
	require.Equal(t, []byte("window-data"), gotEvent.Data)
}

func TestService_SubmitEvent_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SubmitEvent(context.Background(), &SubmitEventRequest{
		Event: &EventProto{Type: EventType_EVENT_TYPE_WINDOW_FOCUS_CHANGE},
	})
	require.Error(t, err)
}

// --- StreamD: Chat ---

func TestService_SendChatMessage(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatform, gotMessage string
	sd.SendChatMessageFunc = func(ctx context.Context, platform, accountID, message string) error {
		gotPlatform = platform
		gotMessage = message
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.SendChatMessage(context.Background(), &SendChatMessageRequest{
		PlatformId: "twitch",
		Message:    "Hello, chat!",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatform)
	require.Equal(t, "Hello, chat!", gotMessage)
}

func TestService_SendChatMessage_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SendChatMessage(context.Background(), &SendChatMessageRequest{PlatformId: "t", Message: "m"})
	require.Error(t, err)
}

func TestService_InjectPlatformEvent(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotEvent backend.ChatEvent
	sd.InjectPlatformEventFunc = func(ctx context.Context, event backend.ChatEvent) error {
		gotEvent = event
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.InjectPlatformEvent(context.Background(), &InjectPlatformEventRequest{
		Event: &ChatEventProto{
			Id:                "evt-1",
			CreatedAtUnixNano: 1234567890,
			User: &ChatUserProto{
				Id:   "user-1",
				Name: "TestUser",
			},
			Message: &ChatMessageContentProto{
				Content: "Hello world",
			},
		},
	})
	require.NoError(t, err)
	require.Equal(t, "evt-1", gotEvent.ID)
	require.Equal(t, int64(1234567890), gotEvent.CreatedAtUnixNano)
	require.Equal(t, "user-1", gotEvent.User.ID)
	require.Equal(t, "TestUser", gotEvent.User.Name)
	require.NotNil(t, gotEvent.MessageContent)
	require.Equal(t, "Hello world", gotEvent.MessageContent.Content)
}

func TestService_InjectPlatformEvent_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.InjectPlatformEvent(context.Background(), &InjectPlatformEventRequest{
		Event: &ChatEventProto{Id: "e"},
	})
	require.Error(t, err)
}

func TestService_RemoveChatMessage(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotMessageID string
	sd.RemoveChatMessageFunc = func(ctx context.Context, platID string, messageID string) error {
		gotPlatID = platID
		gotMessageID = messageID
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RemoveChatMessage(context.Background(), &RemoveChatMessageRequest{
		PlatformId: "twitch",
		MessageId:  "msg-123",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "msg-123", gotMessageID)
}

func TestService_RemoveChatMessage_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveChatMessage(context.Background(), &RemoveChatMessageRequest{PlatformId: "t", MessageId: "m"})
	require.Error(t, err)
}

func TestService_BanUser(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotUserID, gotReason string
	var gotDuration int64
	sd.BanUserFunc = func(ctx context.Context, platID string, userID string, reason string, durationSeconds int64) error {
		gotPlatID = platID
		gotUserID = userID
		gotReason = reason
		gotDuration = durationSeconds
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.BanUser(context.Background(), &BanUserRequest{
		PlatformId:      "twitch",
		UserId:          "user-bad",
		Reason:          "spamming",
		DurationSeconds: 3600,
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "user-bad", gotUserID)
	require.Equal(t, "spamming", gotReason)
	require.Equal(t, int64(3600), gotDuration)
}

func TestService_BanUser_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.BanUser(context.Background(), &BanUserRequest{PlatformId: "t", UserId: "u"})
	require.Error(t, err)
}

// --- StreamD: Social ---

func TestService_Shoutout(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotTargetUserName string
	sd.ShoutoutFunc = func(ctx context.Context, platID string, targetUserName string) error {
		gotPlatID = platID
		gotTargetUserName = targetUserName
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.Shoutout(context.Background(), &ShoutoutRequest{
		PlatformId:     "twitch",
		TargetUserName: "streamer123",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "streamer123", gotTargetUserName)
}

func TestService_Shoutout_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.Shoutout(context.Background(), &ShoutoutRequest{PlatformId: "t", TargetUserName: "u"})
	require.Error(t, err)
}

func TestService_RaidTo(t *testing.T) {
	sd := backend.NewMockStreamD()
	var gotPlatID, gotTargetChannel string
	sd.RaidToFunc = func(ctx context.Context, platID string, targetChannel string) error {
		gotPlatID = platID
		gotTargetChannel = targetChannel
		return nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.RaidTo(context.Background(), &RaidToRequest{
		PlatformId:    "twitch",
		TargetChannel: "friend_channel",
	})
	require.NoError(t, err)
	require.Equal(t, "twitch", gotPlatID)
	require.Equal(t, "friend_channel", gotTargetChannel)
}

func TestService_RaidTo_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RaidTo(context.Background(), &RaidToRequest{PlatformId: "t", TargetChannel: "c"})
	require.Error(t, err)
}

func TestService_GetPeerIDs(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.GetPeerIDsFunc = func(ctx context.Context) ([]string, error) {
		return []string{"peer-1", "peer-2", "peer-3"}, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.GetPeerIDs(context.Background(), &GetPeerIDsRequest{})
	require.NoError(t, err)
	require.Equal(t, []string{"peer-1", "peer-2", "peer-3"}, resp.GetPeerIds())
}

func TestService_GetPeerIDs_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetPeerIDs(context.Background(), &GetPeerIDsRequest{})
	require.Error(t, err)
}

// --- StreamD: AI ---

func TestService_LLMGenerate(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.LLMGenerateFunc = func(ctx context.Context, prompt string) (string, error) {
		require.Equal(t, "Tell me a joke", prompt)
		return "Why did the chicken cross the road?", nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	resp, err := client.LLMGenerate(context.Background(), &LLMGenerateRequest{
		Prompt: "Tell me a joke",
	})
	require.NoError(t, err)
	require.Equal(t, "Why did the chicken cross the road?", resp.GetText())
}

func TestService_LLMGenerate_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.LLMGenerate(context.Background(), &LLMGenerateRequest{Prompt: "hello"})
	require.Error(t, err)
}

// --- StreamD: System ---

func TestService_Restart(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.Restart(context.Background(), &RestartRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("Restart"))
}

func TestService_Restart_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.Restart(context.Background(), &RestartRequest{})
	require.Error(t, err)
}

func TestService_EXPERIMENTAL_ReinitStreamControllers(t *testing.T) {
	sd := backend.NewMockStreamD()

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	_, err := client.EXPERIMENTAL_ReinitStreamControllers(context.Background(), &ReinitStreamControllersRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, sd.CallCount("ReinitStreamControllers"))
}

func TestService_EXPERIMENTAL_ReinitStreamControllers_NoStreamD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.EXPERIMENTAL_ReinitStreamControllers(context.Background(), &ReinitStreamControllersRequest{})
	require.Error(t, err)
}

// --- FFStream: Extended ---

func TestService_FFSetLoggingLevel(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotLevel int
	ff.FFSetLoggingLevelFunc = func(ctx context.Context, level int) error {
		gotLevel = level
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.FFSetLoggingLevel(context.Background(), &FFSetLoggingLevelRequest{
		Level: LoggingLevel(5),
	})
	require.NoError(t, err)
	require.Equal(t, 5, gotLevel)
}

func TestService_FFSetLoggingLevel_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.FFSetLoggingLevel(context.Background(), &FFSetLoggingLevelRequest{Level: 3})
	require.Error(t, err)
}

func TestService_RemoveOutput(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotID uint64
	ff.RemoveOutputFunc = func(ctx context.Context, id uint64) error {
		gotID = id
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.RemoveOutput(context.Background(), &RemoveOutputRequest{
		OutputId: "42",
	})
	require.NoError(t, err)
	require.Equal(t, uint64(42), gotID)
}

func TestService_RemoveOutput_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.RemoveOutput(context.Background(), &RemoveOutputRequest{OutputId: "1"})
	require.Error(t, err)
}

func TestService_RemoveOutput_InvalidID(t *testing.T) {
	ff := backend.NewMockFFStream()
	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.RemoveOutput(context.Background(), &RemoveOutputRequest{OutputId: "not-a-number"})
	require.Error(t, err)
}

func TestService_GetCurrentOutput(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetCurrentOutputFunc = func(ctx context.Context) (*backend.CurrentOutput, error) {
		return &backend.CurrentOutput{
			ID:         7,
			MaxBitRate: 5000000,
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetCurrentOutput(context.Background(), &GetCurrentOutputRequest{})
	require.NoError(t, err)
	require.Equal(t, "7", resp.GetOutput().GetOutputId())
}

func TestService_GetCurrentOutput_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetCurrentOutput(context.Background(), &GetCurrentOutputRequest{})
	require.Error(t, err)
}

func TestService_SwitchOutputByProps(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotProps backend.SenderProps
	ff.SwitchOutputByPropsFunc = func(ctx context.Context, props backend.SenderProps) error {
		gotProps = props
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SwitchOutputByProps(context.Background(), &SwitchOutputByPropsRequest{
		Props: map[string]string{
			"max_bitrate":   "5000000",
			"video_bitrate": "4000000",
			"audio_bitrate": "128000",
			"video_width":   "1920",
			"video_height":  "1080",
		},
	})
	require.NoError(t, err)
	require.Equal(t, uint64(5000000), gotProps.MaxBitRate)
	require.Equal(t, uint64(4000000), gotProps.Config.VideoBitRate)
	require.Equal(t, uint64(128000), gotProps.Config.AudioBitRate)
	require.Equal(t, uint32(1920), gotProps.Config.VideoWidth)
	require.Equal(t, uint32(1080), gotProps.Config.VideoHeight)
}

func TestService_SwitchOutputByProps_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SwitchOutputByProps(context.Background(), &SwitchOutputByPropsRequest{Props: map[string]string{}})
	require.Error(t, err)
}

func TestService_GetOutputSRTStats(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetOutputSRTStatsFunc = func(ctx context.Context, outputID int32) (*backend.SRTStats, error) {
		return &backend.SRTStats{
			PktSent:       1000,
			PktRecv:       950,
			PktSendLoss:   10,
			PktRecvLoss:   5,
			PktRetrans:    20,
			RTTMS:         15.5,
			BandwidthMbps: 10.2,
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetOutputSRTStats(context.Background(), &GetOutputSRTStatsRequest{})
	require.NoError(t, err)
	require.Equal(t, int64(1000), resp.GetStats().GetPktSent())
	require.Equal(t, int64(950), resp.GetStats().GetPktReceived())
	require.Equal(t, int64(10), resp.GetStats().GetPktSendLoss())
	require.Equal(t, int64(5), resp.GetStats().GetPktRecvLoss())
	require.Equal(t, int64(20), resp.GetStats().GetPktRetrans())
	require.InDelta(t, 15.5, resp.GetStats().GetRttMs(), 0.01)
	require.InDelta(t, 10.2, resp.GetStats().GetBandwidthMbps(), 0.01)
}

func TestService_GetOutputSRTStats_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetOutputSRTStats(context.Background(), &GetOutputSRTStatsRequest{})
	require.Error(t, err)
}

func TestService_GetSRTFlagInt(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetSRTFlagIntFunc = func(ctx context.Context, flag backend.SRTFlagInt) (int64, error) {
		require.Equal(t, backend.SRTFlagInt(1), flag)
		return 200, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetSRTFlagInt(context.Background(), &GetSRTFlagIntRequest{
		Flag: SRTFlagInt_SRT_FLAG_INT_LATENCY,
	})
	require.NoError(t, err)
	require.Equal(t, int64(200), resp.GetValue())
}

func TestService_GetSRTFlagInt_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetSRTFlagInt(context.Background(), &GetSRTFlagIntRequest{Flag: SRTFlagInt_SRT_FLAG_INT_LATENCY})
	require.Error(t, err)
}

func TestService_SetSRTFlagInt(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotFlag backend.SRTFlagInt
	var gotValue int64
	ff.SetSRTFlagIntFunc = func(ctx context.Context, flag backend.SRTFlagInt, value int64) error {
		gotFlag = flag
		gotValue = value
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetSRTFlagInt(context.Background(), &SetSRTFlagIntRequest{
		Flag:  SRTFlagInt_SRT_FLAG_INT_LATENCY,
		Value: 300,
	})
	require.NoError(t, err)
	require.Equal(t, backend.SRTFlagInt(1), gotFlag)
	require.Equal(t, int64(300), gotValue)
}

func TestService_SetSRTFlagInt_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetSRTFlagInt(context.Background(), &SetSRTFlagIntRequest{Flag: SRTFlagInt_SRT_FLAG_INT_LATENCY, Value: 100})
	require.Error(t, err)
}

func TestService_FFEnd(t *testing.T) {
	ff := backend.NewMockFFStream()

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.FFEnd(context.Background(), &FFEndRequest{})
	require.NoError(t, err)
	require.Equal(t, 1, ff.CallCount("End"))
}

func TestService_FFEnd_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.FFEnd(context.Background(), &FFEndRequest{})
	require.Error(t, err)
}

func TestService_GetPipelines(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetPipelinesFunc = func(ctx context.Context) ([]backend.Pipeline, error) {
		return []backend.Pipeline{
			{ID: "pipe-1", Description: "Main pipeline"},
			{ID: "pipe-2", Description: "Backup pipeline"},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetPipelines(context.Background(), &GetPipelinesRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetPipelines(), 2)
	require.Equal(t, "pipe-1", resp.GetPipelines()[0].GetId())
	require.Equal(t, "Main pipeline", resp.GetPipelines()[0].GetDescription())
	require.Equal(t, "pipe-2", resp.GetPipelines()[1].GetId())
}

func TestService_GetPipelines_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetPipelines(context.Background(), &GetPipelinesRequest{})
	require.Error(t, err)
}

func TestService_GetVideoAutoBitRateConfig(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetAutoBitRateVideoConfigFunc = func(ctx context.Context) (*backend.AutoBitRateVideoConfig, error) {
		return &backend.AutoBitRateVideoConfig{
			Enabled:   true,
			MinHeight: 480,
			MaxHeight: 1080,
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetVideoAutoBitRateConfig(context.Background(), &GetVideoAutoBitRateConfigRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(480), resp.GetConfig().GetMinBitrate())
	require.Equal(t, uint64(1080), resp.GetConfig().GetMaxBitrate())
}

func TestService_GetVideoAutoBitRateConfig_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetVideoAutoBitRateConfig(context.Background(), &GetVideoAutoBitRateConfigRequest{})
	require.Error(t, err)
}

func TestService_SetVideoAutoBitRateConfig(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotConfig backend.AutoBitRateVideoConfig
	ff.SetAutoBitRateVideoConfigFunc = func(ctx context.Context, cfg backend.AutoBitRateVideoConfig) error {
		gotConfig = cfg
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetVideoAutoBitRateConfig(context.Background(), &SetVideoAutoBitRateConfigRequest{
		Config: &AutoBitRateVideoConfigProto{
			MinBitrate: 720,
			MaxBitrate: 1080,
		},
	})
	require.NoError(t, err)
	require.Equal(t, uint32(720), gotConfig.MinHeight)
	require.Equal(t, uint32(1080), gotConfig.MaxHeight)
}

func TestService_SetVideoAutoBitRateConfig_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetVideoAutoBitRateConfig(context.Background(), &SetVideoAutoBitRateConfigRequest{
		Config: &AutoBitRateVideoConfigProto{},
	})
	require.Error(t, err)
}

func TestService_GetVideoAutoBitRateCalculator(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetVideoAutoBitRateCalculatorFunc = func(ctx context.Context) ([]byte, error) {
		return []byte("calculator-config-data"), nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetVideoAutoBitRateCalculator(context.Background(), &GetVideoAutoBitRateCalculatorRequest{})
	require.NoError(t, err)
	require.Equal(t, []byte("calculator-config-data"), resp.GetCalculator().GetConfig())
}

func TestService_GetVideoAutoBitRateCalculator_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetVideoAutoBitRateCalculator(context.Background(), &GetVideoAutoBitRateCalculatorRequest{})
	require.Error(t, err)
}

func TestService_SetVideoAutoBitRateCalculator(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotConfig []byte
	ff.SetVideoAutoBitRateCalculatorFunc = func(ctx context.Context, config []byte) error {
		gotConfig = config
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetVideoAutoBitRateCalculator(context.Background(), &SetVideoAutoBitRateCalculatorRequest{
		Calculator: &AutoBitRateCalculatorProto{
			Config: []byte("new-calc-config"),
		},
	})
	require.NoError(t, err)
	require.Equal(t, []byte("new-calc-config"), gotConfig)
}

func TestService_SetVideoAutoBitRateCalculator_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetVideoAutoBitRateCalculator(context.Background(), &SetVideoAutoBitRateCalculatorRequest{
		Calculator: &AutoBitRateCalculatorProto{Config: []byte("c")},
	})
	require.Error(t, err)
}

func TestService_GetInputsInfo(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.GetInputsInfoFunc = func(ctx context.Context) ([]backend.InputInfo, error) {
		return []backend.InputInfo{
			{ID: 1, Priority: 10, URL: "rtmp://input1", IsActive: true, Suppressed: false},
			{ID: 2, Priority: 20, URL: "srt://input2", IsActive: false, Suppressed: true},
		}, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	resp, err := client.GetInputsInfo(context.Background(), &GetInputsInfoRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetInputs(), 2)
	require.Equal(t, "1", resp.GetInputs()[0].GetId())
	require.Equal(t, uint32(10), resp.GetInputs()[0].GetPriority())
	require.Equal(t, "rtmp://input1", resp.GetInputs()[0].GetUrl())
	require.True(t, resp.GetInputs()[0].GetIsActive())
	require.False(t, resp.GetInputs()[0].GetIsSuppressed())
	require.Equal(t, "2", resp.GetInputs()[1].GetId())
	require.True(t, resp.GetInputs()[1].GetIsSuppressed())
}

func TestService_GetInputsInfo_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.GetInputsInfo(context.Background(), &GetInputsInfoRequest{})
	require.Error(t, err)
}

func TestService_SetInputCustomOption(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotInputID, gotKey, gotValue string
	ff.SetInputCustomOptionFunc = func(ctx context.Context, inputID string, key string, value string) error {
		gotInputID = inputID
		gotKey = key
		gotValue = value
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetInputCustomOption(context.Background(), &SetInputCustomOptionRequest{
		InputId: "input-1",
		Option: &CustomOptionProto{
			Key:   "latency",
			Value: "200",
		},
	})
	require.NoError(t, err)
	require.Equal(t, "input-1", gotInputID)
	require.Equal(t, "latency", gotKey)
	require.Equal(t, "200", gotValue)
}

func TestService_SetInputCustomOption_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetInputCustomOption(context.Background(), &SetInputCustomOptionRequest{
		InputId: "i",
		Option:  &CustomOptionProto{Key: "k", Value: "v"},
	})
	require.Error(t, err)
}

func TestService_SetStopInput(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotInputID string
	ff.SetStopInputFunc = func(ctx context.Context, inputID string) error {
		gotInputID = inputID
		return nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.SetStopInput(context.Background(), &SetStopInputRequest{
		InputId: "input-1",
	})
	require.NoError(t, err)
	require.Equal(t, "input-1", gotInputID)
}

func TestService_SetStopInput_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetStopInput(context.Background(), &SetStopInputRequest{InputId: "i"})
	require.Error(t, err)
}

func TestService_InjectDiagnostics(t *testing.T) {
	ff := backend.NewMockFFStream()
	var gotDiag *backend.Diagnostics
	ff.InjectDiagnosticsFunc = func(ctx context.Context, diagnostics *backend.Diagnostics, durationNs uint64) error {
		gotDiag = diagnostics
		return nil
	}

	fpsInput := int32(30)
	fpsOutput := int32(29)
	bitrateVideo := int64(5000000)
	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	_, err := client.InjectDiagnostics(context.Background(), &InjectDiagnosticsRequest{
		Diagnostics: &DiagnosticsProto{
			FpsInput:     &fpsInput,
			FpsOutput:    &fpsOutput,
			BitrateVideo: &bitrateVideo,
			Channels:     []int32{1, 6, 11},
		},
	})
	require.NoError(t, err)
	require.NotNil(t, gotDiag)
	require.NotNil(t, gotDiag.FPSInput)
	require.Equal(t, int32(30), *gotDiag.FPSInput)
	require.NotNil(t, gotDiag.FPSOutput)
	require.Equal(t, int32(29), *gotDiag.FPSOutput)
	require.NotNil(t, gotDiag.BitrateVideo)
	require.Equal(t, int64(5000000), *gotDiag.BitrateVideo)
	require.Equal(t, []int32{1, 6, 11}, gotDiag.Channels)
}

func TestService_InjectDiagnostics_NoFFStream(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.InjectDiagnostics(context.Background(), &InjectDiagnosticsRequest{
		Diagnostics: &DiagnosticsProto{},
	})
	require.Error(t, err)
}

func TestService_ChannelQuality(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	// Initially empty
	resp, err := client.GetChannelQuality(context.Background(), &GetChannelQualityRequest{})
	require.NoError(t, err)
	require.Empty(t, resp.GetChannels())

	// Set channel qualities
	_, err = client.SetChannelQuality(context.Background(), &SetChannelQualityRequest{
		Channels: []*ChannelQualityEntry{
			{Label: "S", Quality: -5},
			{Label: "P", Quality: 0},
			{Label: "W", Quality: 5},
		},
	})
	require.NoError(t, err)

	// Get should return what we set
	resp, err = client.GetChannelQuality(context.Background(), &GetChannelQualityRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetChannels(), 3)
	require.Equal(t, "S", resp.GetChannels()[0].GetLabel())
	require.Equal(t, int32(-5), resp.GetChannels()[0].GetQuality())
	require.Equal(t, "P", resp.GetChannels()[1].GetLabel())
	require.Equal(t, int32(0), resp.GetChannels()[1].GetQuality())
	require.Equal(t, "W", resp.GetChannels()[2].GetLabel())
	require.Equal(t, int32(5), resp.GetChannels()[2].GetQuality())

	// Overwrite with different count
	_, err = client.SetChannelQuality(context.Background(), &SetChannelQualityRequest{
		Channels: []*ChannelQualityEntry{
			{Label: "X", Quality: 10},
		},
	})
	require.NoError(t, err)

	resp, err = client.GetChannelQuality(context.Background(), &GetChannelQualityRequest{})
	require.NoError(t, err)
	require.Len(t, resp.GetChannels(), 1)
	require.Equal(t, "X", resp.GetChannels()[0].GetLabel())
	require.Equal(t, int32(10), resp.GetChannels()[0].GetQuality())
}

// --- Streaming RPC tests ---

func TestService_SubscribeToStreamsChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamsChangesFunc = func(ctx context.Context) (<-chan backend.Stream, error) {
		ch := make(chan backend.Stream, 2)
		ch <- backend.Stream{ID: backend.StreamIDFullyQualified{PlatformID: "twitch"}, IsActive: true, Title: "Live"}
		ch <- backend.Stream{ID: backend.StreamIDFullyQualified{PlatformID: "youtube"}, IsActive: false, Title: "Ended"}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamsChanges(context.Background(), &SubscribeToStreamsChangesRequest{})
	require.NoError(t, err)

	ev1, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "twitch", ev1.GetStream().GetId().GetPlatformId())
	require.True(t, ev1.GetStream().GetIsActive())

	ev2, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "youtube", ev2.GetStream().GetId().GetPlatformId())
	require.False(t, ev2.GetStream().GetIsActive())
}

func TestService_SubscribeToConfigChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToConfigChangesFunc = func(ctx context.Context) (<-chan string, error) {
		ch := make(chan string, 2)
		ch <- "config-v1"
		ch <- "config-v2"
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToConfigChanges(context.Background(), &SubscribeToConfigChangesRequest{})
	require.NoError(t, err)

	ev1, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "config-v1", ev1.GetConfig())

	ev2, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "config-v2", ev2.GetConfig())
}

func TestService_SubscribeToStreamServersChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamServersChangesFunc = func(ctx context.Context) (<-chan backend.StreamServer, error) {
		ch := make(chan backend.StreamServer, 1)
		ch <- backend.StreamServer{ID: "srv1", Type: "rtmp", ListenAddr: ":1935"}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamServersChanges(context.Background(), &SubscribeToStreamServersChangesRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "srv1", ev.GetServer().GetId())
	require.Equal(t, "rtmp", ev.GetServer().GetType())
}

func TestService_SubscribeToStreamSourcesChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamSourcesChangesFunc = func(ctx context.Context) (<-chan backend.StreamSource, error) {
		ch := make(chan backend.StreamSource, 1)
		ch <- backend.StreamSource{ID: "src1", URL: "rtmp://test", IsActive: true}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamSourcesChanges(context.Background(), &SubscribeToStreamSourcesChangesRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "src1", ev.GetSource().GetId())
	require.True(t, ev.GetSource().GetIsActive())
}

func TestService_SubscribeToStreamSinksChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamSinksChangesFunc = func(ctx context.Context) (<-chan backend.StreamSink, error) {
		ch := make(chan backend.StreamSink, 1)
		ch <- backend.StreamSink{ID: "sink1", URL: "rtmp://out"}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamSinksChanges(context.Background(), &SubscribeToStreamSinksChangesRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "sink1", ev.GetSink().GetId())
}

func TestService_SubscribeToStreamForwardsChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamForwardsChangesFunc = func(ctx context.Context) (<-chan backend.StreamForward, error) {
		ch := make(chan backend.StreamForward, 1)
		ch <- backend.StreamForward{SourceID: "cam1", SinkID: "twitch", Enabled: true}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamForwardsChanges(context.Background(), &SubscribeToStreamForwardsChangesRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "cam1", ev.GetForward().GetSourceId())
	require.True(t, ev.GetForward().GetEnabled())
}

func TestService_SubscribeToStreamPlayersChanges(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToStreamPlayersChangesFunc = func(ctx context.Context) (<-chan backend.StreamPlayer, error) {
		ch := make(chan backend.StreamPlayer, 1)
		ch <- backend.StreamPlayer{ID: "p1", Title: "Player 1", Position: 10.0}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToStreamPlayersChanges(context.Background(), &SubscribeToStreamPlayersChangesRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "p1", ev.GetPlayer().GetId())
	require.Equal(t, "Player 1", ev.GetPlayer().GetTitle())
}

func TestService_SubscribeToVariable(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToVariableFunc = func(ctx context.Context, key string) (<-chan []byte, error) {
		require.Equal(t, "my_var", key)
		ch := make(chan []byte, 2)
		ch <- []byte("value1")
		ch <- []byte("value2")
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToVariable(context.Background(), &SubscribeToVariableRequest{Key: "my_var"})
	require.NoError(t, err)

	ev1, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "my_var", ev1.GetKey())
	require.Equal(t, []byte("value1"), ev1.GetValue())

	ev2, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, []byte("value2"), ev2.GetValue())
}

func TestService_SubscribeToOAuthRequests(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.SubscribeToOAuthRequestsFunc = func(ctx context.Context) (<-chan backend.OAuthRequest, error) {
		ch := make(chan backend.OAuthRequest, 1)
		ch <- backend.OAuthRequest{RequestID: "req-1", AuthURL: "https://auth.test", PlatformID: "twitch"}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.SubscribeToOAuthRequests(context.Background(), &SubscribeToOAuthRequestsRequest{})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "req-1", ev.GetRequestId())
	require.Equal(t, "https://auth.test", ev.GetAuthUrl())
	require.Equal(t, "twitch", ev.GetPlatformId())
}

func TestService_StreamPlayerEndChan(t *testing.T) {
	sd := backend.NewMockStreamD()
	sd.PlayerEndChanFunc = func(ctx context.Context, playerID string) (<-chan struct{}, error) {
		require.Equal(t, "player-1", playerID)
		ch := make(chan struct{}, 1)
		ch <- struct{}{}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, nil, sd)
	defer cleanup()

	stream, err := client.StreamPlayerEndChan(context.Background(), &StreamPlayerEndChanRequest{
		PlayerId: "player-1",
	})
	require.NoError(t, err)

	ev, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "player-1", ev.GetPlayerId())
}

func TestService_FFWaitChan(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.WaitChanFunc = func(ctx context.Context) (<-chan struct{}, error) {
		ch := make(chan struct{}, 1)
		ch <- struct{}{}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	stream, err := client.FFWaitChan(context.Background(), &FFWaitChanRequest{})
	require.NoError(t, err)

	_, err = stream.Recv()
	require.NoError(t, err)
}

func TestService_FFMonitor(t *testing.T) {
	ff := backend.NewMockFFStream()
	ff.MonitorFunc = func(ctx context.Context, req backend.MonitorRequest) (<-chan backend.MonitorEvent, error) {
		ch := make(chan backend.MonitorEvent, 2)
		ch <- backend.MonitorEvent{EventType: "bitrate_change", Timestamp: 1000}
		ch <- backend.MonitorEvent{EventType: "quality_drop", Timestamp: 2000}
		close(ch)
		return ch, nil
	}

	client, cleanup := testServer(t, ff, nil)
	defer cleanup()

	stream, err := client.FFMonitor(context.Background(), &FFMonitorRequest{})
	require.NoError(t, err)

	ev1, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "bitrate_change", ev1.GetEventType())
	require.Equal(t, int64(1000), ev1.GetTimestamp())

	ev2, err := stream.Recv()
	require.NoError(t, err)
	require.Equal(t, "quality_drop", ev2.GetEventType())
}

// =========================================================================
// Backend Addresses
// =========================================================================

func TestService_SetBackendAddresses(t *testing.T) {
	srv := NewServer(nil, nil, nil)

	var capturedFF, capturedSD, capturedAVD string
	srv.SetBackendAddressHandlers(
		func(ctx context.Context, ffAddr, sdAddr, avdAddr string) error {
			capturedFF = ffAddr
			capturedSD = sdAddr
			capturedAVD = avdAddr
			return nil
		},
		func(ctx context.Context) (string, string, string, error) {
			return capturedFF, capturedSD, capturedAVD, nil
		},
	)

	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = srv.Serve(ctx, lis) }()
	time.Sleep(50 * time.Millisecond)

	conn, err := grpc.NewClient(lis.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer conn.Close()

	client := NewWingOutServiceClient(conn)

	_, err = client.SetBackendAddresses(ctx, &SetBackendAddressesRequest{
		FfstreamAddr: "10.0.0.1:3593",
		StreamdAddr:  "10.0.0.2:3594",
	})
	require.NoError(t, err)
	require.Equal(t, "10.0.0.1:3593", capturedFF)
	require.Equal(t, "10.0.0.2:3594", capturedSD)
}

func TestService_GetBackendAddresses(t *testing.T) {
	srv := NewServer(nil, nil, nil)

	srv.SetBackendAddressHandlers(
		func(ctx context.Context, ffAddr, sdAddr, avdAddr string) error { return nil },
		func(ctx context.Context) (string, string, string, error) {
			return "192.168.1.10:3593", "192.168.1.20:3594", "192.168.1.30:3596", nil
		},
	)

	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = srv.Serve(ctx, lis) }()
	time.Sleep(50 * time.Millisecond)

	conn, err := grpc.NewClient(lis.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer conn.Close()

	client := NewWingOutServiceClient(conn)

	resp, err := client.GetBackendAddresses(ctx, &GetBackendAddressesRequest{})
	require.NoError(t, err)
	require.Equal(t, "192.168.1.10:3593", resp.GetFfstreamAddr())
	require.Equal(t, "192.168.1.20:3594", resp.GetStreamdAddr())
}

func TestService_BackendAddresses_NoHandler(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.SetBackendAddresses(context.Background(), &SetBackendAddressesRequest{
		FfstreamAddr: "10.0.0.1:3593",
	})
	require.Error(t, err)

	_, err = client.GetBackendAddresses(context.Background(), &GetBackendAddressesRequest{})
	require.Error(t, err)
}

func TestServer_HotSwapBackends(t *testing.T) {
	ff1 := backend.NewMockFFStream()
	ff1.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate: backend.BitRateInfo{Video: 1_000_000},
		}, nil
	}

	ff2 := backend.NewMockFFStream()
	ff2.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate: backend.BitRateInfo{Video: 9_000_000},
		}, nil
	}

	srv := NewServer(ff1, nil, nil)

	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = srv.Serve(ctx, lis) }()
	time.Sleep(50 * time.Millisecond)

	conn, err := grpc.NewClient(lis.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer conn.Close()

	client := NewWingOutServiceClient(conn)

	// Query with first backend
	resp, err := client.GetBitRates(ctx, &GetBitRatesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(1_000_000), resp.GetInputBitRate().GetVideo())

	// Hot-swap to second backend
	srv.SetFFStream(ff2)

	// Query again - should see new backend's values
	resp, err = client.GetBitRates(ctx, &GetBitRatesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(9_000_000), resp.GetInputBitRate().GetVideo())
}

// --- AVD service tests ---

func TestService_AVDListRoutes(t *testing.T) {
	avd := backend.NewMockAVD()
	avd.ListRoutesFunc = func(ctx context.Context) ([]backend.AVDRouteInfo, error) {
		return []backend.AVDRouteInfo{
			{
				Path:      "/live/cam1",
				IsServing: true,
				Forwardings: []backend.AVDForwardingInfo{
					{Index: 0, HasPrivacyBlur: true, HasDeblemish: false},
					{Index: 1, HasPrivacyBlur: false, HasDeblemish: true},
				},
			},
			{
				Path:      "/live/cam2",
				IsServing: false,
				Forwardings: []backend.AVDForwardingInfo{
					{Index: 0, HasPrivacyBlur: true, HasDeblemish: true},
				},
			},
		}, nil
	}

	client, cleanup := testServerWithAVD(t, nil, nil, avd)
	defer cleanup()

	resp, err := client.AVDListRoutes(context.Background(), &AVDListRoutesRequest{})
	require.NoError(t, err)

	routes := resp.GetRoutes()
	require.Len(t, routes, 2)

	require.Equal(t, "/live/cam1", routes[0].GetPath())
	require.True(t, routes[0].GetIsServing())
	require.Len(t, routes[0].GetForwardings(), 2)
	require.Equal(t, int32(0), routes[0].GetForwardings()[0].GetIndex())
	require.True(t, routes[0].GetForwardings()[0].GetHasPrivacyBlur())
	require.False(t, routes[0].GetForwardings()[0].GetHasDeblemish())
	require.Equal(t, int32(1), routes[0].GetForwardings()[1].GetIndex())
	require.False(t, routes[0].GetForwardings()[1].GetHasPrivacyBlur())
	require.True(t, routes[0].GetForwardings()[1].GetHasDeblemish())

	require.Equal(t, "/live/cam2", routes[1].GetPath())
	require.False(t, routes[1].GetIsServing())
	require.Len(t, routes[1].GetForwardings(), 1)
	require.True(t, routes[1].GetForwardings()[0].GetHasPrivacyBlur())
	require.True(t, routes[1].GetForwardings()[0].GetHasDeblemish())
}

func TestService_AVDListRoutes_NoAVD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AVDListRoutes(context.Background(), &AVDListRoutesRequest{})
	require.Error(t, err)
	require.Contains(t, err.Error(), "avd backend is not available")
}

func TestService_AVDGetPrivacyBlur(t *testing.T) {
	avd := backend.NewMockAVD()
	avd.GetPrivacyBlurFunc = func(ctx context.Context, routePath string, forwardingIndex int32) (*backend.AVDPrivacyBlurState, error) {
		require.Equal(t, "/live/cam1", routePath)
		require.Equal(t, int32(2), forwardingIndex)
		return &backend.AVDPrivacyBlurState{
			Enabled:           true,
			BlurRadius:        25.5,
			PixelateBlockSize: 8,
		}, nil
	}

	client, cleanup := testServerWithAVD(t, nil, nil, avd)
	defer cleanup()

	resp, err := client.AVDGetPrivacyBlur(context.Background(), &AVDGetPrivacyBlurRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 2,
	})
	require.NoError(t, err)
	require.True(t, resp.GetEnabled())
	require.InDelta(t, 25.5, resp.GetBlurRadius(), 0.001)
	require.Equal(t, int64(8), resp.GetPixelateBlockSize())
}

func TestService_AVDGetPrivacyBlur_NoAVD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AVDGetPrivacyBlur(context.Background(), &AVDGetPrivacyBlurRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 0,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "avd backend is not available")
}

func TestService_AVDSetPrivacyBlur(t *testing.T) {
	avd := backend.NewMockAVD()
	var capturedEnabled *bool
	var capturedRadius *float64
	var capturedBlockSize *int64
	avd.SetPrivacyBlurFunc = func(ctx context.Context, routePath string, forwardingIndex int32, enabled *bool, blurRadius *float64, pixelateBlockSize *int64) error {
		require.Equal(t, "/live/cam1", routePath)
		require.Equal(t, int32(0), forwardingIndex)
		capturedEnabled = enabled
		capturedRadius = blurRadius
		capturedBlockSize = pixelateBlockSize
		return nil
	}

	client, cleanup := testServerWithAVD(t, nil, nil, avd)
	defer cleanup()

	enabled := true
	radius := 42.0
	_, err := client.AVDSetPrivacyBlur(context.Background(), &AVDSetPrivacyBlurRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 0,
		Enabled:         &enabled,
		BlurRadius:      &radius,
	})
	require.NoError(t, err)
	require.NotNil(t, capturedEnabled)
	require.True(t, *capturedEnabled)
	require.NotNil(t, capturedRadius)
	require.InDelta(t, 42.0, *capturedRadius, 0.001)
	require.Nil(t, capturedBlockSize)
}

func TestService_AVDSetPrivacyBlur_NoAVD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	enabled := true
	_, err := client.AVDSetPrivacyBlur(context.Background(), &AVDSetPrivacyBlurRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 0,
		Enabled:         &enabled,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "avd backend is not available")
}

func TestService_AVDGetDeblemish(t *testing.T) {
	avd := backend.NewMockAVD()
	avd.GetDeblemishFunc = func(ctx context.Context, routePath string, forwardingIndex int32) (*backend.AVDDeblemishState, error) {
		require.Equal(t, "/live/cam1", routePath)
		require.Equal(t, int32(1), forwardingIndex)
		return &backend.AVDDeblemishState{
			Enabled:  true,
			SigmaS:   60.0,
			SigmaR:   0.45,
			Diameter: 15,
		}, nil
	}

	client, cleanup := testServerWithAVD(t, nil, nil, avd)
	defer cleanup()

	resp, err := client.AVDGetDeblemish(context.Background(), &AVDGetDeblemishRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 1,
	})
	require.NoError(t, err)
	require.True(t, resp.GetEnabled())
	require.InDelta(t, 60.0, resp.GetSigmaS(), 0.001)
	require.InDelta(t, 0.45, resp.GetSigmaR(), 0.001)
	require.Equal(t, int64(15), resp.GetDiameter())
}

func TestService_AVDGetDeblemish_NoAVD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	_, err := client.AVDGetDeblemish(context.Background(), &AVDGetDeblemishRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 0,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "avd backend is not available")
}

func TestService_AVDSetDeblemish(t *testing.T) {
	avd := backend.NewMockAVD()
	var capturedEnabled *bool
	var capturedSigmaS *float64
	var capturedSigmaR *float64
	var capturedDiameter *int64
	avd.SetDeblemishFunc = func(ctx context.Context, routePath string, forwardingIndex int32, enabled *bool, sigmaS *float64, sigmaR *float64, diameter *int64) error {
		require.Equal(t, "/live/cam1", routePath)
		require.Equal(t, int32(3), forwardingIndex)
		capturedEnabled = enabled
		capturedSigmaS = sigmaS
		capturedSigmaR = sigmaR
		capturedDiameter = diameter
		return nil
	}

	client, cleanup := testServerWithAVD(t, nil, nil, avd)
	defer cleanup()

	enabled := false
	sigmaR := 0.75
	diameter := int64(20)
	_, err := client.AVDSetDeblemish(context.Background(), &AVDSetDeblemishRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 3,
		Enabled:         &enabled,
		SigmaR:          &sigmaR,
		Diameter:        &diameter,
	})
	require.NoError(t, err)
	require.NotNil(t, capturedEnabled)
	require.False(t, *capturedEnabled)
	require.Nil(t, capturedSigmaS)
	require.NotNil(t, capturedSigmaR)
	require.InDelta(t, 0.75, *capturedSigmaR, 0.001)
	require.NotNil(t, capturedDiameter)
	require.Equal(t, int64(20), *capturedDiameter)
}

func TestService_AVDSetDeblemish_NoAVD(t *testing.T) {
	client, cleanup := testServer(t, nil, nil)
	defer cleanup()

	enabled := true
	_, err := client.AVDSetDeblemish(context.Background(), &AVDSetDeblemishRequest{
		RoutePath:       "/live/cam1",
		ForwardingIndex: 0,
		Enabled:         &enabled,
	})
	require.Error(t, err)
	require.Contains(t, err.Error(), "avd backend is not available")
}
