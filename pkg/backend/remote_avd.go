package backend

import (
	"context"
	"fmt"

	avdgrpc "github.com/xaionaro-go/avd/pkg/management/grpc/proto/avdmanagementgrpc"
	"google.golang.org/grpc"
)

var _ AVDBackend = (*RemoteAVD)(nil)

// RemoteAVD implements AVDBackend by connecting to a remote AVD gRPC server.
type RemoteAVD struct {
	conn   *grpc.ClientConn
	client avdgrpc.AvdServiceClient
}

// NewRemoteAVD dials the given address and returns a remote AVD client.
func NewRemoteAVD(addr string) (*RemoteAVD, error) {
	creds := dialCredentials(addr)
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("dial avd at %s: %w", addr, err)
	}
	return &RemoteAVD{
		conn:   conn,
		client: avdgrpc.NewAvdServiceClient(conn),
	}, nil
}

// Close closes the gRPC connection.
func (r *RemoteAVD) Close() error {
	return r.conn.Close()
}

func (r *RemoteAVD) ListRoutes(
	ctx context.Context,
) ([]AVDRouteInfo, error) {
	routesResp, err := r.client.ListRoutes(ctx, &avdgrpc.ListRoutesRequest{})
	if err != nil {
		return nil, fmt.Errorf("list routes: %w", err)
	}

	controlsResp, err := r.client.ListFilterControls(ctx, &avdgrpc.ListFilterControlsRequest{})
	if err != nil {
		return nil, fmt.Errorf("list filter controls: %w", err)
	}

	// Build a lookup of filter controls keyed by (route_path, forwarding_index).
	type controlKey struct {
		RoutePath       string
		ForwardingIndex int32
	}
	controlMap := make(map[controlKey]*avdgrpc.FilterControlInfo, len(controlsResp.GetControls()))
	for _, c := range controlsResp.GetControls() {
		controlMap[controlKey{c.GetRoutePath(), c.GetForwardingIndex()}] = c
	}

	// Build route info from route paths + filter controls.
	routePaths := routesResp.GetRoutePaths()
	routes := make([]AVDRouteInfo, 0, len(routePaths))
	for _, path := range routePaths {
		route := AVDRouteInfo{
			Path:      path,
			IsServing: true,
		}

		// Collect all forwardings for this route path.
		for key, ctrl := range controlMap {
			if key.RoutePath != path {
				continue
			}
			route.Forwardings = append(route.Forwardings, AVDForwardingInfo{
				Index:          ctrl.GetForwardingIndex(),
				HasPrivacyBlur: ctrl.GetHasPrivacyBlur(),
				HasDeblemish:   ctrl.GetHasDeblemish(),
			})
		}

		routes = append(routes, route)
	}

	return routes, nil
}

func (r *RemoteAVD) GetPrivacyBlur(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
) (*AVDPrivacyBlurState, error) {
	resp, err := r.client.GetPrivacyBlur(ctx, &avdgrpc.GetPrivacyBlurRequest{
		RoutePath:       routePath,
		ForwardingIndex: forwardingIndex,
	})
	if err != nil {
		return nil, err
	}
	return &AVDPrivacyBlurState{
		Enabled:           resp.GetEnabled(),
		BlurRadius:        resp.GetBlurRadius(),
		PixelateBlockSize: resp.GetPixelateBlockSize(),
	}, nil
}

func (r *RemoteAVD) SetPrivacyBlur(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
	enabled *bool,
	blurRadius *float64,
	pixelateBlockSize *int64,
) error {
	req := &avdgrpc.SetPrivacyBlurRequest{
		RoutePath:       routePath,
		ForwardingIndex: forwardingIndex,
	}
	if enabled != nil {
		req.Enabled = enabled
	}
	if blurRadius != nil {
		req.BlurRadius = blurRadius
	}
	if pixelateBlockSize != nil {
		req.PixelateBlockSize = pixelateBlockSize
	}
	_, err := r.client.SetPrivacyBlur(ctx, req)
	return err
}

func (r *RemoteAVD) GetDeblemish(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
) (*AVDDeblemishState, error) {
	resp, err := r.client.GetDeblemish(ctx, &avdgrpc.GetDeblemishRequest{
		RoutePath:       routePath,
		ForwardingIndex: forwardingIndex,
	})
	if err != nil {
		return nil, err
	}
	return &AVDDeblemishState{
		Enabled:  resp.GetEnabled(),
		SigmaS:   resp.GetSigmaS(),
		SigmaR:   resp.GetSigmaR(),
		Diameter: resp.GetDiameter(),
	}, nil
}

func (r *RemoteAVD) SetDeblemish(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
	enabled *bool,
	sigmaS *float64,
	sigmaR *float64,
	diameter *int64,
) error {
	req := &avdgrpc.SetDeblemishRequest{
		RoutePath:       routePath,
		ForwardingIndex: forwardingIndex,
	}
	if enabled != nil {
		req.Enabled = enabled
	}
	if sigmaS != nil {
		req.SigmaS = sigmaS
	}
	if sigmaR != nil {
		req.SigmaR = sigmaR
	}
	if diameter != nil {
		req.Diameter = diameter
	}
	_, err := r.client.SetDeblemish(ctx, req)
	return err
}
