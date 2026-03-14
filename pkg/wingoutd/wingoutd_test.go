package wingoutd

import (
	"context"
	"encoding/json"
	"net"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/api"
	"github.com/xaionaro-go/wingout2/pkg/backend"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func findFreePort(t *testing.T) string {
	t.Helper()
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	addr := lis.Addr().String()
	lis.Close()
	return addr
}

func TestNew_ValidConfig(t *testing.T) {
	cfg := Config{
		Mode:               backend.BackendModeRemote,
		ListenAddr:         ":0",
		RemoteFFStreamAddr: "127.0.0.1:3593",
	}
	d, err := New(cfg)
	require.NoError(t, err)
	require.NotNil(t, d)
	require.Equal(t, cfg.Mode, d.Config().Mode)
}

func TestNew_InvalidConfig(t *testing.T) {
	cfg := Config{
		Mode: "invalid",
	}
	d, err := New(cfg)
	require.Error(t, err)
	require.Nil(t, d)
}

func TestDaemon_SetBackends(t *testing.T) {
	cfg := Config{
		Mode:       backend.BackendModeEmbedded,
		ListenAddr: ":0",
	}
	d, err := New(cfg)
	require.NoError(t, err)

	ff := backend.NewMockFFStream()
	sd := backend.NewMockStreamD()

	d.SetFFStream(ff)
	d.SetStreamD(sd)
}

func TestDaemon_Run_and_Connect(t *testing.T) {
	addr := findFreePort(t)
	cfg := Config{
		Mode:       backend.BackendModeEmbedded,
		ListenAddr: addr,
	}
	d, err := New(cfg)
	require.NoError(t, err)

	ff := backend.NewMockFFStream()
	ff.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return &backend.BitRates{
			InputBitRate: backend.BitRateInfo{Video: 5_000_000},
		}, nil
	}
	sd := backend.NewMockStreamD()

	d.SetFFStream(ff)
	d.SetStreamD(sd)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	errCh := make(chan error, 1)
	go func() {
		errCh <- d.Run(ctx)
	}()

	// Wait for server to start
	time.Sleep(100 * time.Millisecond)

	// Connect as client
	conn, err := grpc.NewClient(
		addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	require.NoError(t, err)
	defer conn.Close()

	client := api.NewWingOutServiceClient(conn)

	// Test Ping
	pingResp, err := client.Ping(ctx, &api.PingRequest{Payload: "test"})
	require.NoError(t, err)
	require.Equal(t, "test", pingResp.GetPayload())

	// Test GetBitRates
	brResp, err := client.GetBitRates(ctx, &api.GetBitRatesRequest{})
	require.NoError(t, err)
	require.Equal(t, uint64(5_000_000), brResp.GetInputBitRate().GetVideo())

	// Test GetBackendMode
	modeResp, err := client.GetBackendMode(ctx, &api.GetBackendModeRequest{})
	require.NoError(t, err)
	require.Equal(t, "hybrid", modeResp.GetMode())

	// Stop daemon
	cancel()

	select {
	case err := <-errCh:
		require.ErrorIs(t, err, context.Canceled)
	case <-time.After(5 * time.Second):
		t.Fatal("daemon did not stop in time")
	}
}

func TestDaemon_Stop(t *testing.T) {
	addr := findFreePort(t)
	cfg := Config{
		Mode:       backend.BackendModeEmbedded,
		ListenAddr: addr,
	}
	d, err := New(cfg)
	require.NoError(t, err)
	d.SetFFStream(backend.NewMockFFStream())

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = d.Run(ctx) }()
	time.Sleep(100 * time.Millisecond)

	d.Stop()
}

func TestDaemon_SetGetBackendAddresses(t *testing.T) {
	addr := findFreePort(t)
	cfg := Config{
		Mode:       backend.BackendModeRemote,
		ListenAddr: addr,
	}
	d, err := New(cfg)
	require.NoError(t, err)
	d.SetFFStream(backend.NewMockFFStream())
	d.SetStreamD(backend.NewMockStreamD())

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() { _ = d.Run(ctx) }()
	time.Sleep(100 * time.Millisecond)

	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)
	defer conn.Close()

	client := api.NewWingOutServiceClient(conn)

	// Get initial addresses (empty since we used test injection, not remote config)
	getResp, err := client.GetBackendAddresses(ctx, &api.GetBackendAddressesRequest{})
	require.NoError(t, err)
	require.Equal(t, "", getResp.GetFfstreamAddr())
	require.Equal(t, "", getResp.GetStreamdAddr())

	// Set addresses - this will fail to connect to non-existent servers,
	// but we can't easily mock remote backends here, so test the handler path only
	// by verifying the Get reflects what we Set.
	// Note: SetBackendAddresses tries to actually connect, which will fail for fake addresses.
	// We just test Get returns what was initially configured.
}

func TestDaemon_HandshakeFormat(t *testing.T) {
	// Verify the handshake JSON format
	srv := api.NewServer(nil, nil, nil)
	var output []byte
	err := srv.WriteHandshake("127.0.0.1:5000", func(data []byte) {
		output = data
	})
	require.NoError(t, err)

	var info api.HandshakeInfo
	err = json.Unmarshal(output[:len(output)-1], &info) // strip newline
	require.NoError(t, err)
	require.Equal(t, "127.0.0.1:5000", info.GRPCAddr)
	require.NotEmpty(t, info.Version)
}
