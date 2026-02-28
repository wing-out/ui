package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/xaionaro-go/wingout2/pkg/backend"
	"github.com/xaionaro-go/wingout2/pkg/wingoutd"
)

func main() {
	mode := flag.String("mode", "remote", "Backend mode: embedded, remote, or hybrid")
	listenAddr := flag.String("listen", "127.0.0.1:3595", "gRPC listen address")
	ffstreamAddr := flag.String("ffstream-addr", "", "Remote FFStream gRPC address")
	streamdAddr := flag.String("streamd-addr", "", "Remote StreamD gRPC address")
	logLevel := flag.Int("log-level", 5, "Logging level (0=none, 7=trace)")
	flag.Parse()

	cfg := wingoutd.Config{
		Mode:               backend.BackendMode(*mode),
		ListenAddr:         *listenAddr,
		RemoteFFStreamAddr: *ffstreamAddr,
		RemoteStreamDAddr:  *streamdAddr,
		LogLevel:           *logLevel,
	}

	d, err := wingoutd.New(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigCh
		cancel()
	}()

	if err := d.Run(ctx); err != nil && err != context.Canceled {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
