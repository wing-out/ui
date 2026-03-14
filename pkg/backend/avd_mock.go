package backend

import (
	"context"
)

// MockAVD is a mock implementation of AVDBackend for testing.
type MockAVD struct {
	ListRoutesFunc     func(ctx context.Context) ([]AVDRouteInfo, error)
	GetPrivacyBlurFunc func(ctx context.Context, routePath string, forwardingIndex int32) (*AVDPrivacyBlurState, error)
	SetPrivacyBlurFunc func(ctx context.Context, routePath string, forwardingIndex int32, enabled *bool, blurRadius *float64, pixelateBlockSize *int64) error
	GetDeblemishFunc   func(ctx context.Context, routePath string, forwardingIndex int32) (*AVDDeblemishState, error)
	SetDeblemishFunc   func(ctx context.Context, routePath string, forwardingIndex int32, enabled *bool, sigmaS *float64, sigmaR *float64, diameter *int64) error
}

// NewMockAVD creates a new MockAVD with default no-op implementations.
func NewMockAVD() *MockAVD {
	return &MockAVD{}
}

func (m *MockAVD) ListRoutes(ctx context.Context) ([]AVDRouteInfo, error) {
	if m.ListRoutesFunc != nil {
		return m.ListRoutesFunc(ctx)
	}
	return nil, nil
}

func (m *MockAVD) GetPrivacyBlur(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
) (*AVDPrivacyBlurState, error) {
	if m.GetPrivacyBlurFunc != nil {
		return m.GetPrivacyBlurFunc(ctx, routePath, forwardingIndex)
	}
	return &AVDPrivacyBlurState{}, nil
}

func (m *MockAVD) SetPrivacyBlur(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
	enabled *bool,
	blurRadius *float64,
	pixelateBlockSize *int64,
) error {
	if m.SetPrivacyBlurFunc != nil {
		return m.SetPrivacyBlurFunc(ctx, routePath, forwardingIndex, enabled, blurRadius, pixelateBlockSize)
	}
	return nil
}

func (m *MockAVD) GetDeblemish(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
) (*AVDDeblemishState, error) {
	if m.GetDeblemishFunc != nil {
		return m.GetDeblemishFunc(ctx, routePath, forwardingIndex)
	}
	return &AVDDeblemishState{}, nil
}

func (m *MockAVD) SetDeblemish(
	ctx context.Context,
	routePath string,
	forwardingIndex int32,
	enabled *bool,
	sigmaS *float64,
	sigmaR *float64,
	diameter *int64,
) error {
	if m.SetDeblemishFunc != nil {
		return m.SetDeblemishFunc(ctx, routePath, forwardingIndex, enabled, sigmaS, sigmaR, diameter)
	}
	return nil
}
