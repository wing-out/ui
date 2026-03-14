package wingoutd

import (
	"context"
	"fmt"
	"io"
	"net"
	"sync"

	"github.com/xaionaro-go/wingout2/pkg/api"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

// Daemon is the main wingoutd process that manages backends and serves the unified API.
type Daemon struct {
	config   Config
	mu       sync.Mutex
	server   *api.Server
	ffstream backend.FFStreamBackend
	streamd  backend.StreamDBackend
	avd      backend.AVDBackend

	// Current remote addresses (may differ from config if changed at runtime).
	remoteFFStreamAddr string
	remoteStreamDAddr  string
	remoteAVDAddr      string
}

// New creates a new Daemon with the given configuration.
// It initializes backends according to the mode but does not start serving.
func New(cfg Config) (*Daemon, error) {
	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("invalid config: %w", err)
	}

	d := &Daemon{
		config:             cfg,
		remoteFFStreamAddr: cfg.RemoteFFStreamAddr,
		remoteStreamDAddr:  cfg.RemoteStreamDAddr,
		remoteAVDAddr:      cfg.RemoteAVDAddr,
	}

	return d, nil
}

// SetFFStream sets the FFStream backend (used for dependency injection in tests).
func (d *Daemon) SetFFStream(ff backend.FFStreamBackend) {
	d.ffstream = ff
}

// SetStreamD sets the StreamD backend (used for dependency injection in tests).
func (d *Daemon) SetStreamD(sd backend.StreamDBackend) {
	d.streamd = sd
}

// SetAVD sets the AVD backend (used for dependency injection in tests).
func (d *Daemon) SetAVD(avd backend.AVDBackend) {
	d.avd = avd
}

// Config returns the daemon configuration.
func (d *Daemon) Config() Config {
	return d.config
}

// Run starts the daemon: initializes backends and starts the gRPC server.
// It blocks until the context is cancelled.
func (d *Daemon) Run(ctx context.Context) error {
	// Create initial remote backends from config addresses (if set and not overridden by test injection).
	if d.ffstream == nil && d.remoteFFStreamAddr != "" {
		ff, err := backend.NewRemoteFFStream(d.remoteFFStreamAddr)
		if err != nil {
			return fmt.Errorf("connect to remote ffstream at %s: %w", d.remoteFFStreamAddr, err)
		}
		d.ffstream = ff
	}
	if d.streamd == nil && d.remoteStreamDAddr != "" {
		sd, err := backend.NewRemoteStreamD(d.remoteStreamDAddr)
		if err != nil {
			return fmt.Errorf("connect to remote streamd at %s: %w", d.remoteStreamDAddr, err)
		}
		d.streamd = sd
	}
	if d.avd == nil && d.remoteAVDAddr != "" {
		avd, err := backend.NewRemoteAVD(d.remoteAVDAddr)
		if err != nil {
			return fmt.Errorf("connect to remote avd at %s: %w", d.remoteAVDAddr, err)
		}
		d.avd = avd
	}

	srv := api.NewServer(d.ffstream, d.streamd, d.avd)

	// Register backend address handlers.
	srv.SetBackendAddressHandlers(d.handleSetBackendAddresses, d.handleGetBackendAddresses)

	d.mu.Lock()
	d.server = srv
	d.mu.Unlock()

	lis, err := net.Listen("tcp", d.config.ListenAddr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", d.config.ListenAddr, err)
	}

	// Write handshake to stdout so the frontend knows how to connect
	addr := lis.Addr().String()
	if err := srv.WriteHandshake(addr, func(data []byte) {
		fmt.Print(string(data))
	}); err != nil {
		lis.Close()
		return fmt.Errorf("write handshake: %w", err)
	}

	return srv.Serve(ctx, lis)
}

// handleSetBackendAddresses creates new remote backends and hot-swaps them into the server.
func (d *Daemon) handleSetBackendAddresses(ctx context.Context, ffAddr, sdAddr, avdAddr string) error {
	d.mu.Lock()
	srv := d.server
	d.mu.Unlock()

	if srv == nil {
		return fmt.Errorf("server not running")
	}

	// Close old remote backends if they implement io.Closer.
	if ffAddr != d.remoteFFStreamAddr {
		if closer, ok := srv.FFStream().(io.Closer); ok {
			closer.Close()
		}
		if ffAddr != "" {
			ff, err := backend.NewRemoteFFStream(ffAddr)
			if err != nil {
				return fmt.Errorf("connect to remote ffstream at %s: %w", ffAddr, err)
			}
			srv.SetFFStream(ff)
		} else {
			srv.SetFFStream(nil)
		}
		d.mu.Lock()
		d.remoteFFStreamAddr = ffAddr
		d.mu.Unlock()
	}

	if sdAddr != d.remoteStreamDAddr {
		if closer, ok := srv.StreamD().(io.Closer); ok {
			closer.Close()
		}
		if sdAddr != "" {
			sd, err := backend.NewRemoteStreamD(sdAddr)
			if err != nil {
				return fmt.Errorf("connect to remote streamd at %s: %w", sdAddr, err)
			}
			srv.SetStreamD(sd)
		} else {
			srv.SetStreamD(nil)
		}
		d.mu.Lock()
		d.remoteStreamDAddr = sdAddr
		d.mu.Unlock()
	}

	if avdAddr != d.remoteAVDAddr {
		if closer, ok := srv.AVD().(io.Closer); ok {
			closer.Close()
		}
		if avdAddr != "" {
			avd, err := backend.NewRemoteAVD(avdAddr)
			if err != nil {
				return fmt.Errorf("connect to remote avd at %s: %w", avdAddr, err)
			}
			srv.SetAVD(avd)
		} else {
			srv.SetAVD(nil)
		}
		d.mu.Lock()
		d.remoteAVDAddr = avdAddr
		d.mu.Unlock()
	}

	return nil
}

// handleGetBackendAddresses returns the current backend addresses.
func (d *Daemon) handleGetBackendAddresses(ctx context.Context) (string, string, string, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.remoteFFStreamAddr, d.remoteStreamDAddr, d.remoteAVDAddr, nil
}

// Stop gracefully stops the daemon.
func (d *Daemon) Stop() {
	d.mu.Lock()
	srv := d.server
	d.mu.Unlock()
	if srv != nil {
		srv.Stop()
	}
}
