package wingoutd

import (
	"fmt"

	"github.com/xaionaro-go/wingout2/pkg/backend"
)

// Config holds the daemon configuration.
type Config struct {
	// Mode determines how backends are initialized.
	Mode backend.BackendMode `json:"mode" yaml:"mode"`

	// ListenAddr is the gRPC listen address (e.g., ":3595" or "127.0.0.1:3595").
	ListenAddr string `json:"listen_addr" yaml:"listen_addr"`

	// RemoteFFStreamAddr is the address of a remote FFStream gRPC server.
	// Used when Mode is "remote" or "hybrid" (with remote FFStream).
	RemoteFFStreamAddr string `json:"remote_ffstream_addr,omitempty" yaml:"remote_ffstream_addr,omitempty"`

	// RemoteStreamDAddr is the address of a remote StreamD gRPC server.
	// Used when Mode is "remote" or "hybrid" (with remote StreamD).
	RemoteStreamDAddr string `json:"remote_streamd_addr,omitempty" yaml:"remote_streamd_addr,omitempty"`

	// RemoteAVDAddr is the address of a remote AVD gRPC server.
	RemoteAVDAddr string `json:"remote_avd_addr,omitempty" yaml:"remote_avd_addr,omitempty"`

	// LogLevel is the logging level (0=none, 7=trace).
	LogLevel int `json:"log_level" yaml:"log_level"`
}

// DefaultConfig returns a sensible default configuration.
func DefaultConfig() Config {
	return Config{
		Mode:       backend.BackendModeRemote,
		ListenAddr: "127.0.0.1:3595",
		LogLevel:   5,
	}
}

// Validate checks the configuration for errors.
func (c *Config) Validate() error {
	switch c.Mode {
	case backend.BackendModeEmbedded:
		// No remote addrs needed
	case backend.BackendModeRemote:
		// Remote addresses are optional at startup; they can be set at runtime via SetBackendAddresses RPC.
	case backend.BackendModeHybrid:
		// At least one remote or embedded component
	default:
		return fmt.Errorf("unknown backend mode: %q", c.Mode)
	}

	if c.ListenAddr == "" {
		return fmt.Errorf("listen_addr is required")
	}

	return nil
}
