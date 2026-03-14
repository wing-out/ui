package api

import (
	"context"
	"fmt"

	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func (s *wingOutService) getAVD() backend.AVDBackend {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.avd
}

func (s *wingOutService) setAVD(avd backend.AVDBackend) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.avd = avd
}

func (s *wingOutService) requireAVD() error {
	if s.getAVD() == nil {
		return fmt.Errorf("avd backend is not available")
	}
	return nil
}

func (s *wingOutService) AVDListRoutes(
	ctx context.Context,
	_ *AVDListRoutesRequest,
) (*AVDListRoutesReply, error) {
	if err := s.requireAVD(); err != nil {
		return nil, err
	}
	routes, err := s.getAVD().ListRoutes(ctx)
	if err != nil {
		return nil, err
	}

	protoRoutes := make([]*AVDRouteInfo, 0, len(routes))
	for _, r := range routes {
		fwds := make([]*AVDForwardingInfo, 0, len(r.Forwardings))
		for _, f := range r.Forwardings {
			fwds = append(fwds, &AVDForwardingInfo{
				Index:          f.Index,
				HasPrivacyBlur: f.HasPrivacyBlur,
				HasDeblemish:   f.HasDeblemish,
			})
		}
		protoRoutes = append(protoRoutes, &AVDRouteInfo{
			Path:        r.Path,
			Description: r.Description,
			IsServing:   r.IsServing,
			Forwardings: fwds,
		})
	}

	return &AVDListRoutesReply{Routes: protoRoutes}, nil
}

func (s *wingOutService) AVDGetPrivacyBlur(
	ctx context.Context,
	req *AVDGetPrivacyBlurRequest,
) (*AVDGetPrivacyBlurReply, error) {
	if err := s.requireAVD(); err != nil {
		return nil, err
	}
	state, err := s.getAVD().GetPrivacyBlur(ctx, req.GetRoutePath(), req.GetForwardingIndex())
	if err != nil {
		return nil, err
	}
	return &AVDGetPrivacyBlurReply{
		Enabled:           state.Enabled,
		BlurRadius:        state.BlurRadius,
		PixelateBlockSize: state.PixelateBlockSize,
	}, nil
}

func (s *wingOutService) AVDSetPrivacyBlur(
	ctx context.Context,
	req *AVDSetPrivacyBlurRequest,
) (*AVDSetPrivacyBlurReply, error) {
	if err := s.requireAVD(); err != nil {
		return nil, err
	}
	err := s.getAVD().SetPrivacyBlur(
		ctx,
		req.GetRoutePath(),
		req.GetForwardingIndex(),
		req.Enabled,
		req.BlurRadius,
		req.PixelateBlockSize,
	)
	if err != nil {
		return nil, err
	}
	return &AVDSetPrivacyBlurReply{}, nil
}

func (s *wingOutService) AVDGetDeblemish(
	ctx context.Context,
	req *AVDGetDeblemishRequest,
) (*AVDGetDeblemishReply, error) {
	if err := s.requireAVD(); err != nil {
		return nil, err
	}
	state, err := s.getAVD().GetDeblemish(ctx, req.GetRoutePath(), req.GetForwardingIndex())
	if err != nil {
		return nil, err
	}
	return &AVDGetDeblemishReply{
		Enabled:  state.Enabled,
		SigmaS:   state.SigmaS,
		SigmaR:   state.SigmaR,
		Diameter: state.Diameter,
	}, nil
}

func (s *wingOutService) AVDSetDeblemish(
	ctx context.Context,
	req *AVDSetDeblemishRequest,
) (*AVDSetDeblemishReply, error) {
	if err := s.requireAVD(); err != nil {
		return nil, err
	}
	err := s.getAVD().SetDeblemish(
		ctx,
		req.GetRoutePath(),
		req.GetForwardingIndex(),
		req.Enabled,
		req.SigmaS,
		req.SigmaR,
		req.Diameter,
	)
	if err != nil {
		return nil, err
	}
	return &AVDSetDeblemishReply{}, nil
}
