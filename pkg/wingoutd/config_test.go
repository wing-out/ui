package wingoutd

import (
	"testing"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDefaultConfig(t *testing.T) {
	cfg := DefaultConfig()
	require.Equal(t, backend.BackendModeRemote, cfg.Mode)
	require.Equal(t, "127.0.0.1:3595", cfg.ListenAddr)
	require.Equal(t, 5, cfg.LogLevel)
}

func TestConfig_Validate(t *testing.T) {
	t.Run("valid_embedded", func(t *testing.T) {
		cfg := Config{
			Mode:       backend.BackendModeEmbedded,
			ListenAddr: ":3595",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("valid_remote_with_ffstream", func(t *testing.T) {
		cfg := Config{
			Mode:               backend.BackendModeRemote,
			ListenAddr:         ":3595",
			RemoteFFStreamAddr: "127.0.0.1:3593",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("valid_remote_with_streamd", func(t *testing.T) {
		cfg := Config{
			Mode:              backend.BackendModeRemote,
			ListenAddr:        ":3595",
			RemoteStreamDAddr: "127.0.0.1:3594",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("valid_remote_with_both", func(t *testing.T) {
		cfg := Config{
			Mode:               backend.BackendModeRemote,
			ListenAddr:         ":3595",
			RemoteFFStreamAddr: "127.0.0.1:3593",
			RemoteStreamDAddr:  "127.0.0.1:3594",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("valid_hybrid", func(t *testing.T) {
		cfg := Config{
			Mode:       backend.BackendModeHybrid,
			ListenAddr: ":3595",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("valid_remote_no_addrs", func(t *testing.T) {
		// Remote addresses are optional at startup; they can be set at runtime via SetBackendAddresses RPC.
		cfg := Config{
			Mode:       backend.BackendModeRemote,
			ListenAddr: ":3595",
		}
		require.NoError(t, cfg.Validate())
	})

	t.Run("invalid_no_listen_addr", func(t *testing.T) {
		cfg := Config{
			Mode: backend.BackendModeEmbedded,
		}
		err := cfg.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "listen_addr")
	})

	t.Run("invalid_unknown_mode", func(t *testing.T) {
		cfg := Config{
			Mode:       "bogus",
			ListenAddr: ":3595",
		}
		err := cfg.Validate()
		require.Error(t, err)
		require.Contains(t, err.Error(), "unknown backend mode")
	})
}
