package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/xaionaro-go/wingout2/pkg/backend"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

// Server is the unified gRPC API server that wraps both FFStream and StreamD backends.
type Server struct {
	service *wingOutService

	grpcServer *grpc.Server
	mu         sync.Mutex
	started    bool
}

// NewServer creates a new unified API server.
// Any backend can be nil if that functionality is not needed.
func NewServer(
	ffstream backend.FFStreamBackend,
	streamd backend.StreamDBackend,
	avd backend.AVDBackend,
) *Server {
	return &Server{
		service: &wingOutService{
			ffstream: ffstream,
			streamd:  streamd,
			avd:      avd,
		},
	}
}

// FFStream returns the FFStream backend (may be nil).
func (s *Server) FFStream() backend.FFStreamBackend {
	return s.service.getFFStream()
}

// StreamD returns the StreamD backend (may be nil).
func (s *Server) StreamD() backend.StreamDBackend {
	return s.service.getStreamD()
}

// SetFFStream hot-swaps the FFStream backend.
func (s *Server) SetFFStream(ff backend.FFStreamBackend) {
	s.service.setFFStream(ff)
}

// SetStreamD hot-swaps the StreamD backend.
func (s *Server) SetStreamD(sd backend.StreamDBackend) {
	s.service.setStreamD(sd)
}

// AVD returns the AVD backend (may be nil).
func (s *Server) AVD() backend.AVDBackend {
	return s.service.getAVD()
}

// SetAVD hot-swaps the AVD backend.
func (s *Server) SetAVD(avd backend.AVDBackend) {
	s.service.setAVD(avd)
}

// SetBackendAddressHandlers registers handlers for the Set/GetBackendAddresses RPCs.
func (s *Server) SetBackendAddressHandlers(setHandler SetBackendAddressesHandler, getHandler GetBackendAddressesHandler) {
	s.service.onSetBackendAddresses = setHandler
	s.service.onGetBackendAddresses = getHandler
}

// HandshakeInfo is written to stdout so the frontend knows how to connect.
type HandshakeInfo struct {
	GRPCAddr string `json:"grpc_addr"`
	Version  string `json:"version"`
}

// Serve starts the gRPC server on the given listener and writes handshake info.
func (s *Server) Serve(ctx context.Context, lis net.Listener) error {
	s.mu.Lock()
	if s.started {
		s.mu.Unlock()
		return fmt.Errorf("server already started")
	}
	s.started = true

	opts := []grpc.ServerOption{}
	s.grpcServer = grpc.NewServer(opts...)

	RegisterWingOutServiceServer(s.grpcServer, s.service)
	reflection.Register(s.grpcServer)
	s.mu.Unlock()

	errCh := make(chan error, 1)
	go func() {
		errCh <- s.grpcServer.Serve(lis)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		s.gracefulStopWithTimeout(5 * time.Second)
		return ctx.Err()
	}
}

// WriteHandshake writes JSON handshake info to the given function.
func (s *Server) WriteHandshake(addr string, writeFn func([]byte)) error {
	info := HandshakeInfo{
		GRPCAddr: addr,
		Version:  "2.0.0",
	}
	data, err := json.Marshal(info)
	if err != nil {
		return fmt.Errorf("marshal handshake: %w", err)
	}
	data = append(data, '\n')
	writeFn(data)
	return nil
}

// Stop gracefully stops the gRPC server.
func (s *Server) Stop() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.grpcServer != nil {
		s.gracefulStopWithTimeout(5 * time.Second)
	}
}

// gracefulStopWithTimeout attempts GracefulStop but falls back to Stop
// if it doesn't complete within the timeout. GracefulStop waits for all
// in-flight RPCs to finish, which blocks forever if a client in the same
// process never disconnects (e.g. Android Activity teardown deadlock).
func (s *Server) gracefulStopWithTimeout(timeout time.Duration) {
	done := make(chan struct{})
	go func() {
		s.grpcServer.GracefulStop()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(timeout):
		s.grpcServer.Stop()
	}
}
