package backend

import (
	"context"
)

// AVDForwardingInfo describes the filter controls available for a single forwarding.
type AVDForwardingInfo struct {
	Index          int32
	HasPrivacyBlur bool
	HasDeblemish   bool
}

// AVDRouteInfo describes a route in the AVD pipeline.
type AVDRouteInfo struct {
	Path        string
	Description string
	IsServing   bool
	Forwardings []AVDForwardingInfo
}

// AVDPrivacyBlurState holds the current privacy blur state.
type AVDPrivacyBlurState struct {
	Enabled           bool
	BlurRadius        float64
	PixelateBlockSize int64
}

// AVDDeblemishState holds the current deblemish state.
type AVDDeblemishState struct {
	Enabled  bool
	SigmaS   float64
	SigmaR   float64
	Diameter int64
}

// AVDBackend abstracts the AVD streaming server management API.
type AVDBackend interface {
	// ListRoutes returns all routes with their forwarding info and available controls.
	ListRoutes(ctx context.Context) ([]AVDRouteInfo, error)

	// GetPrivacyBlur returns the privacy blur state for a route/forwarding.
	GetPrivacyBlur(
		ctx context.Context,
		routePath string,
		forwardingIndex int32,
	) (*AVDPrivacyBlurState, error)

	// SetPrivacyBlur updates the privacy blur state for a route/forwarding.
	SetPrivacyBlur(
		ctx context.Context,
		routePath string,
		forwardingIndex int32,
		enabled *bool,
		blurRadius *float64,
		pixelateBlockSize *int64,
	) error

	// GetDeblemish returns the deblemish state for a route/forwarding.
	GetDeblemish(
		ctx context.Context,
		routePath string,
		forwardingIndex int32,
	) (*AVDDeblemishState, error)

	// SetDeblemish updates the deblemish state for a route/forwarding.
	SetDeblemish(
		ctx context.Context,
		routePath string,
		forwardingIndex int32,
		enabled *bool,
		sigmaS *float64,
		sigmaR *float64,
		diameter *int64,
	) error
}
