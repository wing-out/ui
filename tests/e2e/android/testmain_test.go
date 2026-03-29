//go:build android_e2e

package android

import (
	"context"
	"fmt"
	"net"
	"os"
	"testing"
	"time"

	"github.com/xaionaro-go/wingout2/pkg/api"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

const (
	appStartTimeout  = 30 * time.Second
	elementTimeout   = 10 * time.Second
	screenshotDir    = "/tmp/wingout_e2e_screenshots"
	defaultPackageID = "center.dx.wingout2"
)

// sharedEnv is set up once in TestMain and reused across all tests.
var sharedEnv *testEnv

// testEnv holds the shared test environment.
type testEnv struct {
	adb       *ADB
	srv       *api.Server
	mockFF    *backend.MockFFStream
	mockSD    *backend.MockStreamD
	srvCancel context.CancelFunc
	srvAddr   string
}

func TestMain(m *testing.M) {
	apkPath := os.Getenv("WINGOUT_APK_PATH")
	if apkPath == "" {
		fmt.Println("WINGOUT_APK_PATH not set, skipping Android E2E tests")
		os.Exit(0)
	}

	packageID := os.Getenv("WINGOUT_PACKAGE_ID")
	if packageID == "" {
		packageID = defaultPackageID
	}

	adb := NewADB(apkPath, packageID)

	if err := adb.WaitForBoot(60 * time.Second); err != nil {
		fmt.Fprintf(os.Stderr, "emulator boot failed: %v\n", err)
		os.Exit(1)
	}
	_ = adb.UnlockScreen()

	mockFF := backend.NewMockFFStream()
	mockSD := backend.NewMockStreamD()
	setupMockFFStream(mockFF)
	setupMockStreamD(mockSD)

	srv := api.NewServer(mockFF, mockSD, nil)
	lis, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		fmt.Fprintf(os.Stderr, "listen: %v\n", err)
		os.Exit(1)
	}

	srvCtx, srvCancel := context.WithCancel(context.Background())
	go func() { _ = srv.Serve(srvCtx, lis) }()

	_, port, _ := net.SplitHostPort(lis.Addr().String())
	srvAddr := "10.0.2.2:" + port
	fmt.Printf("gRPC server at %s (emulator addr: %s)\n", lis.Addr().String(), srvAddr)

	_ = adb.InstallAPK()

	sharedEnv = &testEnv{
		adb:       adb,
		srv:       srv,
		mockFF:    mockFF,
		mockSD:    mockSD,
		srvCancel: srvCancel,
		srvAddr:   srvAddr,
	}

	code := m.Run()

	adb.StopApp()
	srv.Stop()
	srvCancel()
	os.Exit(code)
}

func setupMockFFStream(m *backend.MockFFStream) {
	m.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 6000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 4500000, Audio: 128000},
		}, nil
	}
	m.GetLatenciesFunc = func(ctx context.Context) (*backend.Latencies, error) {
		return &backend.Latencies{
			Video: backend.TrackLatencies{SendingUs: 3500, PreTranscodingUs: 1500, TranscodingUs: 2000},
		}, nil
	}
	m.GetInputQualityFunc = func(ctx context.Context) (*backend.QualityReport, error) {
		return &backend.QualityReport{
			Video: backend.StreamQuality{Continuity: 0.998, FrameRate: 29.97},
		}, nil
	}
	m.GetFPSFractionFunc = func(ctx context.Context) (uint32, uint32, error) {
		return 30000, 1001, nil
	}
	m.GetStatsFunc = func(ctx context.Context) (*backend.Stats, error) {
		return &backend.Stats{
			NodeCounters: backend.NodeCounters{
				ReceivedFrames:  10000,
				ProcessedFrames: 9950,
				SentFrames:      9900,
			},
		}, nil
	}
	m.GetPipelinesFunc = func(ctx context.Context) ([]backend.Pipeline, error) {
		return nil, nil
	}
	m.GetVideoAutoBitRateCalculatorFunc = func(ctx context.Context) ([]byte, error) {
		return nil, nil
	}
	m.GetAutoBitRateVideoConfigFunc = func(ctx context.Context) (*backend.AutoBitRateVideoConfig, error) {
		return &backend.AutoBitRateVideoConfig{MinHeight: 480, MaxHeight: 1080}, nil
	}
	m.GetOutputSRTStatsFunc = func(ctx context.Context, outputID int32) (*backend.SRTStats, error) {
		return &backend.SRTStats{}, nil
	}
	m.GetCurrentOutputFunc = func(ctx context.Context) (*backend.CurrentOutput, error) {
		return &backend.CurrentOutput{}, nil
	}
	m.GetInputsInfoFunc = func(ctx context.Context) ([]backend.InputInfo, error) {
		return nil, nil
	}
	m.InjectDiagnosticsFunc = func(ctx context.Context, diagnostics *backend.Diagnostics, durationNs uint64) error {
		return nil
	}
	m.FFSetLoggingLevelFunc = func(ctx context.Context, level int) error {
		return nil
	}
}

func setupMockStreamD(m *backend.MockStreamD) {
	var storedConfig = "# default config"

	m.GetConfigFunc = func(ctx context.Context) (string, error) {
		return storedConfig, nil
	}
	m.SetConfigFunc = func(ctx context.Context, yaml string) error {
		storedConfig = yaml
		return nil
	}
	m.SaveConfigFunc = func(ctx context.Context) error {
		return nil
	}
	m.PingFunc = func(ctx context.Context, payload string) (string, error) {
		return payload, nil
	}
	m.ListProfilesFunc = func(ctx context.Context) ([]backend.Profile, error) {
		return []backend.Profile{
			{Name: "IRL 720p", Description: "720p outdoor streaming"},
			{Name: "Home 1080p", Description: "1080p home studio setup"},
		}, nil
	}
	m.ListStreamForwardsFunc = func(ctx context.Context) ([]backend.StreamForward, error) {
		return []backend.StreamForward{
			{SourceID: "cam0", SinkID: "twitch", SinkType: "rtmp", Enabled: true},
			{SourceID: "cam0", SinkID: "youtube", SinkType: "rtmp", Enabled: true},
			{SourceID: "cam0", SinkID: "kick", SinkType: "rtmp", Enabled: false},
		}, nil
	}
	m.ListStreamServersFunc = func(ctx context.Context) ([]backend.StreamServer, error) {
		return []backend.StreamServer{
			{ID: "rtmp_main", Type: "rtmp", ListenAddr: ":1935"},
			{ID: "srt_backup", Type: "srt", ListenAddr: ":9000"},
		}, nil
	}
	m.ListStreamPlayersFunc = func(ctx context.Context) ([]backend.StreamPlayer, error) {
		return []backend.StreamPlayer{
			{ID: "p1", Title: "Background Music", Link: "http://example.com/music.mp3", Position: 65.0, Length: 240.0},
		}, nil
	}

	// Stream sources
	m.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{
			{ID: "cam0", URL: "rtmp://localhost/cam0", IsActive: true},
			{ID: "cam1", URL: "rtmp://localhost/cam1", IsActive: false},
		}, nil
	}

	// Stream lifecycle
	m.GetStreamsFunc = func(ctx context.Context) ([]backend.Stream, error) {
		return []backend.Stream{}, nil
	}
	m.GetActiveStreamIDsFunc = func(ctx context.Context) ([]backend.StreamIDFullyQualified, error) {
		return nil, nil
	}
	m.StartStreamFunc = func(ctx context.Context, platID string, profileName string) error {
		return nil
	}
	m.EndStreamFunc = func(ctx context.Context, platID string) error {
		return nil
	}

	// Accounts & Platforms
	m.GetPlatformsFunc = func(ctx context.Context) ([]string, error) {
		return []string{"twitch", "youtube", "kick"}, nil
	}
	m.GetAccountsFunc = func(ctx context.Context, platformIDs []string) ([]backend.Account, error) {
		return []backend.Account{}, nil
	}
	m.IsBackendEnabledFunc = func(ctx context.Context, platformID string) (bool, error) {
		return true, nil
	}

	// Variables
	m.GetVariableFunc = func(ctx context.Context, key string) ([]byte, error) {
		return []byte("test-value"), nil
	}
	m.SetVariableFunc = func(ctx context.Context, key string, value []byte) error {
		return nil
	}

	// Logging
	m.SetLoggingLevelFunc = func(ctx context.Context, level int) error {
		return nil
	}
	m.GetLoggingLevelFunc = func(ctx context.Context) (int, error) {
		return 3, nil
	}

	// Cache
	m.ResetCacheFunc = func(ctx context.Context) error {
		return nil
	}
	m.InitCacheFunc = func(ctx context.Context) error {
		return nil
	}

	// Chat
	m.SendChatMessageFunc = func(ctx context.Context, platform, accountID, message string) error {
		return nil
	}
	m.RemoveChatMessageFunc = func(ctx context.Context, platID string, messageID string) error {
		return nil
	}
	m.BanUserFunc = func(ctx context.Context, platID string, userID string, reason string, dur int64) error {
		return nil
	}

	// Social
	m.ShoutoutFunc = func(ctx context.Context, platID string, target string) error {
		return nil
	}
	m.RaidToFunc = func(ctx context.Context, platID string, target string) error {
		return nil
	}
	m.GetPeerIDsFunc = func(ctx context.Context) ([]string, error) {
		return []string{"peer1"}, nil
	}

	// Stream status
	m.GetStreamStatusFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, noCache bool) (*backend.StreamStatus, error) {
		viewers := uint64(42)
		return &backend.StreamStatus{IsActive: true, ViewersCount: &viewers}, nil
	}

	// Apply profile
	m.ApplyProfileFunc = func(ctx context.Context, streamID backend.StreamIDFullyQualified, profileName string) error {
		return nil
	}

	// OAuth
	m.SubmitOAuthCodeFunc = func(ctx context.Context, requestID string, code string) error {
		return nil
	}

	// Stream servers
	m.StartStreamServerFunc = func(ctx context.Context, config backend.StreamServer) error {
		return nil
	}
	m.StopStreamServerFunc = func(ctx context.Context, serverID string) error {
		return nil
	}

	// Sinks
	m.ListStreamSinksFunc = func(ctx context.Context) ([]backend.StreamSink, error) {
		return []backend.StreamSink{
			{ID: "twitch", Type: "rtmp", URL: "rtmp://live.twitch.tv/live/key"},
		}, nil
	}
	m.AddStreamSinkFunc = func(ctx context.Context, sink backend.StreamSink) error {
		return nil
	}
	m.RemoveStreamSinkFunc = func(ctx context.Context, id string) error {
		return nil
	}

	// Sources
	m.AddStreamSourceFunc = func(ctx context.Context, url string) error {
		return nil
	}
	m.RemoveStreamSourceFunc = func(ctx context.Context, id string) error {
		return nil
	}

	// Forwards
	m.AddStreamForwardFunc = func(ctx context.Context, fwd backend.StreamForward) error {
		return nil
	}
	m.UpdateStreamForwardFunc = func(ctx context.Context, fwd backend.StreamForward) error {
		return nil
	}
	m.RemoveStreamForwardFunc = func(ctx context.Context, sourceID, sinkID string) error {
		return nil
	}

	// Players
	m.AddStreamPlayerFunc = func(ctx context.Context, player backend.StreamPlayer) error {
		return nil
	}
	m.RemoveStreamPlayerFunc = func(ctx context.Context, playerID string) error {
		return nil
	}
	m.UpdateStreamPlayerFunc = func(ctx context.Context, player backend.StreamPlayer) error {
		return nil
	}
	m.GetStreamPlayerFunc = func(ctx context.Context, playerID string) (*backend.StreamPlayer, error) {
		return &backend.StreamPlayer{ID: "p1", Title: "Background Music"}, nil
	}
	m.PlayerOpenFunc = func(ctx context.Context, playerID string, url string) error {
		return nil
	}
	m.PlayerCloseFunc = func(ctx context.Context, playerID string) error {
		return nil
	}
	m.PlayerSetPauseFunc = func(ctx context.Context, playerID string, paused bool) error {
		return nil
	}
	m.PlayerStopFunc = func(ctx context.Context, playerID string) error {
		return nil
	}
	m.PlayerGetLagFunc = func(ctx context.Context, playerID string) (float64, error) {
		return 1.5, nil
	}

	// Timers
	m.ListTimersFunc = func(ctx context.Context) ([]backend.Timer, error) {
		return nil, nil
	}
	m.AddTimerFunc = func(ctx context.Context, timer backend.Timer) error {
		return nil
	}
	m.RemoveTimerFunc = func(ctx context.Context, timerID string) error {
		return nil
	}

	// Trigger rules
	m.ListTriggerRulesFunc = func(ctx context.Context) ([]backend.TriggerRule, error) {
		return nil, nil
	}

	// AI
	m.LLMGenerateFunc = func(ctx context.Context, prompt string) (string, error) {
		return "AI response", nil
	}

	// System
	m.RestartFunc = func(ctx context.Context) error {
		return nil
	}
	m.ReinitStreamControllersFunc = func(ctx context.Context) error {
		return nil
	}
}
