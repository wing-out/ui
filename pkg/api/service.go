package api

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"github.com/xaionaro-go/wingout2/pkg/backend"
	"google.golang.org/grpc"
)

// SetBackendAddressesHandler is called when SetBackendAddresses RPC is received.
// It receives the new addresses and should create/swap remote backends.
type SetBackendAddressesHandler func(ctx context.Context, ffstreamAddr, streamdAddr, avdAddr string) error

// GetBackendAddressesHandler is called when GetBackendAddresses RPC is received.
type GetBackendAddressesHandler func(ctx context.Context) (ffstreamAddr, streamdAddr, avdAddr string, err error)

// wingOutService implements the unified gRPC service.
type wingOutService struct {
	UnimplementedWingOutServiceServer

	mu       sync.RWMutex
	ffstream backend.FFStreamBackend
	streamd  backend.StreamDBackend
	avd      backend.AVDBackend

	onSetBackendAddresses SetBackendAddressesHandler
	onGetBackendAddresses GetBackendAddressesHandler

	channelQualities []*ChannelQualityEntry
}

func (s *wingOutService) getFFStream() backend.FFStreamBackend {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.ffstream
}

func (s *wingOutService) getStreamD() backend.StreamDBackend {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.streamd
}

func (s *wingOutService) setFFStream(ff backend.FFStreamBackend) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.ffstream = ff
}

func (s *wingOutService) setStreamD(sd backend.StreamDBackend) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.streamd = sd
}

func (s *wingOutService) requireFFStream() error {
	if s.getFFStream() == nil {
		return fmt.Errorf("ffstream backend is not available")
	}
	return nil
}

func (s *wingOutService) requireStreamD() error {
	if s.getStreamD() == nil {
		return fmt.Errorf("streamd backend is not available")
	}
	return nil
}

// SetChannelQuality stores channel quality values in-memory.
func (s *wingOutService) SetChannelQuality(_ context.Context, req *SetChannelQualityRequest) (*SetChannelQualityReply, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.channelQualities = req.GetChannels()
	return &SetChannelQualityReply{}, nil
}

// GetChannelQuality returns the current channel quality values.
func (s *wingOutService) GetChannelQuality(_ context.Context, _ *GetChannelQualityRequest) (*GetChannelQualityReply, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return &GetChannelQualityReply{
		Channels: s.channelQualities,
	}, nil
}

// SetBackendAddresses handles the RPC to reconfigure backend addresses at runtime.
func (s *wingOutService) SetBackendAddresses(ctx context.Context, req *SetBackendAddressesRequest) (*SetBackendAddressesReply, error) {
	if s.onSetBackendAddresses == nil {
		return nil, fmt.Errorf("backend address reconfiguration is not supported")
	}
	if err := s.onSetBackendAddresses(ctx, req.GetFfstreamAddr(), req.GetStreamdAddr(), req.GetAvdAddr()); err != nil {
		return nil, err
	}
	return &SetBackendAddressesReply{}, nil
}

// GetBackendAddresses handles the RPC to query current backend addresses.
func (s *wingOutService) GetBackendAddresses(ctx context.Context, req *GetBackendAddressesRequest) (*GetBackendAddressesReply, error) {
	if s.onGetBackendAddresses == nil {
		return nil, fmt.Errorf("backend address query is not supported")
	}
	ffAddr, sdAddr, avdAddr, err := s.onGetBackendAddresses(ctx)
	if err != nil {
		return nil, err
	}
	return &GetBackendAddressesReply{
		FfstreamAddr: ffAddr,
		StreamdAddr:  sdAddr,
		AvdAddr:      avdAddr,
	}, nil
}

// Ping implements the health check. It forwards the request to StreamD.
// Returns an error if StreamD is not configured.
func (s *wingOutService) Ping(ctx context.Context, req *PingRequest) (*PingReply, error) {
	if s.getStreamD() == nil {
		return nil, fmt.Errorf("streamd backend is not available")
	}
	resp, err := s.getStreamD().Ping(ctx, req.GetPayload())
	if err != nil {
		return nil, err
	}
	return &PingReply{Payload: resp}, nil
}

// GetBitRates returns current bitrate information from FFStream.
func (s *wingOutService) GetBitRates(ctx context.Context, req *GetBitRatesRequest) (*GetBitRatesReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	br, err := s.getFFStream().GetBitRates(ctx)
	if err != nil {
		return nil, err
	}
	return &GetBitRatesReply{
		InputBitRate:   bitRateInfoToProto(&br.InputBitRate),
		EncodedBitRate: bitRateInfoToProto(&br.EncodedBitRate),
		OutputBitRate:  bitRateInfoToProto(&br.OutputBitRate),
	}, nil
}

// GetLatencies returns pipeline latencies from FFStream.
func (s *wingOutService) GetLatencies(ctx context.Context, req *GetLatenciesRequest) (*GetLatenciesReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	lat, err := s.getFFStream().GetLatencies(ctx)
	if err != nil {
		return nil, err
	}
	return &GetLatenciesReply{
		Audio: trackLatenciesToProto(&lat.Audio),
		Video: trackLatenciesToProto(&lat.Video),
	}, nil
}

// GetInputQuality returns input quality metrics from FFStream.
func (s *wingOutService) GetInputQuality(ctx context.Context, req *GetInputQualityRequest) (*GetInputQualityReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	q, err := s.getFFStream().GetInputQuality(ctx)
	if err != nil {
		return nil, err
	}
	return &GetInputQualityReply{
		Audio: streamQualityToProto(&q.Audio),
		Video: streamQualityToProto(&q.Video),
	}, nil
}

// GetOutputQuality returns output quality metrics from FFStream.
func (s *wingOutService) GetOutputQuality(ctx context.Context, req *GetOutputQualityRequest) (*GetOutputQualityReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	q, err := s.getFFStream().GetOutputQuality(ctx)
	if err != nil {
		return nil, err
	}
	return &GetOutputQualityReply{
		Audio: streamQualityToProto(&q.Audio),
		Video: streamQualityToProto(&q.Video),
	}, nil
}

// GetFPSFraction returns the current FPS fraction from FFStream.
func (s *wingOutService) GetFPSFraction(ctx context.Context, req *GetFPSFractionRequest) (*GetFPSFractionReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	num, den, err := s.getFFStream().GetFPSFraction(ctx)
	if err != nil {
		return nil, err
	}
	return &GetFPSFractionReply{Num: num, Den: den}, nil
}

// SetFPSFraction sets the target FPS fraction.
func (s *wingOutService) SetFPSFraction(ctx context.Context, req *SetFPSFractionRequest) (*SetFPSFractionReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	if err := s.getFFStream().SetFPSFraction(ctx, req.GetNum(), req.GetDen()); err != nil {
		return nil, err
	}
	return &SetFPSFractionReply{}, nil
}

// GetStats returns pipeline statistics from FFStream.
func (s *wingOutService) GetStats(ctx context.Context, req *GetStatsRequest) (*GetStatsReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	stats, err := s.getFFStream().GetStats(ctx)
	if err != nil {
		return nil, err
	}
	return &GetStatsReply{
		ReceivedPackets:  stats.NodeCounters.ReceivedPackets,
		ReceivedFrames:   stats.NodeCounters.ReceivedFrames,
		ProcessedPackets: stats.NodeCounters.ProcessedPackets,
		ProcessedFrames:  stats.NodeCounters.ProcessedFrames,
		SentPackets:      stats.NodeCounters.SentPackets,
		SentFrames:       stats.NodeCounters.SentFrames,
	}, nil
}

// InjectSubtitles injects subtitle data into the stream.
func (s *wingOutService) InjectSubtitles(ctx context.Context, req *InjectSubtitlesRequest) (*InjectSubtitlesReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	dur := time.Duration(req.GetDurationNs()) * time.Nanosecond
	if err := s.getFFStream().InjectSubtitles(ctx, req.GetData(), dur); err != nil {
		return nil, err
	}
	return &InjectSubtitlesReply{}, nil
}

// InjectData injects arbitrary data into the stream.
func (s *wingOutService) InjectData(ctx context.Context, req *InjectDataRequest) (*InjectDataReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	dur := time.Duration(req.GetDurationNs()) * time.Nanosecond
	if err := s.getFFStream().InjectData(ctx, req.GetData(), dur); err != nil {
		return nil, err
	}
	return &InjectDataReply{}, nil
}

// GetConfig returns the current configuration.
func (s *wingOutService) GetConfig(ctx context.Context, req *GetConfigRequest) (*GetConfigReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	cfg, err := s.getStreamD().GetConfig(ctx)
	if err != nil {
		return nil, err
	}
	return &GetConfigReply{Config: cfg}, nil
}

// SetConfig updates the configuration.
func (s *wingOutService) SetConfig(ctx context.Context, req *SetConfigRequest) (*SetConfigReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SetConfig(ctx, req.GetConfig()); err != nil {
		return nil, err
	}
	return &SetConfigReply{}, nil
}

// SaveConfig persists configuration to disk.
func (s *wingOutService) SaveConfig(ctx context.Context, req *SaveConfigRequest) (*SaveConfigReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SaveConfig(ctx); err != nil {
		return nil, err
	}
	return &SaveConfigReply{}, nil
}

// GetStreamStatus returns the status of a stream.
func (s *wingOutService) GetStreamStatus(ctx context.Context, req *GetStreamStatusRequest) (*GetStreamStatusReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	streamID := backend.StreamIDFullyQualified{
		PlatformID: req.GetPlatformId(),
		AccountID:  req.GetAccountId(),
		StreamID:   req.GetStreamId(),
	}
	status, err := s.getStreamD().GetStreamStatus(ctx, streamID, req.GetNoCache())
	if err != nil {
		return nil, err
	}
	reply := &GetStreamStatusReply{
		IsActive: status.IsActive,
	}
	if status.StartedAt != nil {
		ts := status.StartedAt.Unix()
		reply.StartedAt = &ts
	}
	if status.ViewersCount != nil {
		reply.ViewersCount = status.ViewersCount
	}
	return reply, nil
}

// ListStreamForwards returns all stream forwards.
func (s *wingOutService) ListStreamForwards(ctx context.Context, req *ListStreamForwardsRequest) (*ListStreamForwardsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	fwds, err := s.getStreamD().ListStreamForwards(ctx)
	if err != nil {
		return nil, err
	}
	var protoFwds []*StreamForwardProto
	for _, f := range fwds {
		protoFwds = append(protoFwds, &StreamForwardProto{
			SourceId: f.SourceID,
			SinkId:   f.SinkID,
			SinkType: f.SinkType,
			Enabled:  f.Enabled,
		})
	}
	return &ListStreamForwardsReply{Forwards: protoFwds}, nil
}

// ListStreamServers returns all running stream servers.
func (s *wingOutService) ListStreamServers(ctx context.Context, req *ListStreamServersRequest) (*ListStreamServersReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	servers, err := s.getStreamD().ListStreamServers(ctx)
	if err != nil {
		return nil, err
	}
	var protoServers []*StreamServerProto
	for _, srv := range servers {
		protoServers = append(protoServers, &StreamServerProto{
			Id:         srv.ID,
			Type:       srv.Type,
			ListenAddr: srv.ListenAddr,
		})
	}
	return &ListStreamServersReply{Servers: protoServers}, nil
}

// ListStreamPlayers returns all stream players.
func (s *wingOutService) ListStreamPlayers(ctx context.Context, req *ListStreamPlayersRequest) (*ListStreamPlayersReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	players, err := s.getStreamD().ListStreamPlayers(ctx)
	if err != nil {
		return nil, err
	}
	var protoPlayers []*StreamPlayerProto
	for _, p := range players {
		protoPlayers = append(protoPlayers, &StreamPlayerProto{
			Id:       p.ID,
			Title:    p.Title,
			Link:     p.Link,
			Position: p.Position,
			Length:   p.Length,
			IsPaused: p.IsPaused,
		})
	}
	return &ListStreamPlayersReply{Players: protoPlayers}, nil
}

// ListProfiles returns all streaming profiles.
func (s *wingOutService) ListProfiles(ctx context.Context, req *ListProfilesRequest) (*ListProfilesReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	profiles, err := s.getStreamD().ListProfiles(ctx)
	if err != nil {
		return nil, err
	}
	var protoProfiles []*ProfileProto
	for _, p := range profiles {
		protoProfiles = append(protoProfiles, &ProfileProto{
			Name:        p.Name,
			Description: p.Description,
		})
	}
	return &ListProfilesReply{Profiles: protoProfiles}, nil
}

// SubscribeToChatMessages streams chat messages to the client.
func (s *wingOutService) SubscribeToChatMessages(req *SubscribeToChatMessagesRequest, stream grpc.ServerStreamingServer[ChatMessageProto]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToChatMessages(stream.Context(), req.GetSinceUnixNano(), req.GetLimit(), req.GetStreamId())
	if err != nil {
		return err
	}
	for msg := range ch {
		if err := stream.Send(&ChatMessageProto{
			Id:        msg.ID,
			Platform:  msg.Platform,
			StreamId:  msg.StreamID,
			UserName:  msg.UserName,
			Message:   msg.Message,
			Timestamp: msg.Timestamp,
		}); err != nil {
			return err
		}
	}
	return nil
}

// GetBackendMode returns the current backend mode.
func (s *wingOutService) GetBackendMode(ctx context.Context, req *GetBackendModeRequest) (*GetBackendModeReply, error) {
	mode := "unknown"
	hasFF := s.getFFStream() != nil
	hasSD := s.getStreamD() != nil
	if hasFF && hasSD {
		mode = "hybrid"
	} else if hasFF {
		mode = "ffstream_only"
	} else if hasSD {
		mode = "streamd_only"
	}
	return &GetBackendModeReply{Mode: mode}, nil
}

// --- StreamD: Logging ---

// SetLoggingLevel sets the logging level for StreamD.
func (s *wingOutService) SetLoggingLevel(ctx context.Context, req *SetLoggingLevelRequest) (*SetLoggingLevelReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SetLoggingLevel(ctx, int(req.GetLevel())); err != nil {
		return nil, err
	}
	return &SetLoggingLevelReply{}, nil
}

// GetLoggingLevel returns the current logging level from StreamD.
func (s *wingOutService) GetLoggingLevel(ctx context.Context, req *GetLoggingLevelRequest) (*GetLoggingLevelReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	level, err := s.getStreamD().GetLoggingLevel(ctx)
	if err != nil {
		return nil, err
	}
	return &GetLoggingLevelReply{Level: LoggingLevel(level)}, nil
}

// --- StreamD: Cache ---

// ResetCache resets the StreamD cache.
func (s *wingOutService) ResetCache(ctx context.Context, req *ResetCacheRequest) (*ResetCacheReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().ResetCache(ctx); err != nil {
		return nil, err
	}
	return &ResetCacheReply{}, nil
}

// InitCache initializes the StreamD cache.
func (s *wingOutService) InitCache(ctx context.Context, req *InitCacheRequest) (*InitCacheReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().InitCache(ctx); err != nil {
		return nil, err
	}
	return &InitCacheReply{}, nil
}

// --- StreamD: Stream Lifecycle ---

// SetStreamActive activates or deactivates a stream.
func (s *wingOutService) SetStreamActive(ctx context.Context, req *SetStreamActiveRequest) (*SetStreamActiveReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	streamID := streamIDFromProto(req.GetStreamId())
	if err := s.getStreamD().SetStreamActive(ctx, streamID, req.GetActive()); err != nil {
		return nil, err
	}
	return &SetStreamActiveReply{}, nil
}

// GetStreams returns all streams.
func (s *wingOutService) GetStreams(ctx context.Context, req *GetStreamsRequest) (*GetStreamsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	streams, err := s.getStreamD().GetStreams(ctx)
	if err != nil {
		return nil, err
	}
	var protoStreams []*StreamInfoProto
	for _, st := range streams {
		protoStreams = append(protoStreams, streamInfoToProto(&st))
	}
	return &GetStreamsReply{Streams: protoStreams}, nil
}

// CreateStream creates a new stream.
func (s *wingOutService) CreateStream(ctx context.Context, req *CreateStreamRequest) (*CreateStreamReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().CreateStream(ctx, req.GetPlatformId(), req.GetTitle(), req.GetDescription(), req.GetProfile()); err != nil {
		return nil, err
	}
	return &CreateStreamReply{}, nil
}

// DeleteStream deletes a stream.
func (s *wingOutService) DeleteStream(ctx context.Context, req *DeleteStreamRequest) (*DeleteStreamReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	streamID := streamIDFromProto(req.GetStreamId())
	if err := s.getStreamD().DeleteStream(ctx, streamID); err != nil {
		return nil, err
	}
	return &DeleteStreamReply{}, nil
}

// GetActiveStreamIDs returns all active stream IDs.
func (s *wingOutService) GetActiveStreamIDs(ctx context.Context, req *GetActiveStreamIDsRequest) (*GetActiveStreamIDsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	ids, err := s.getStreamD().GetActiveStreamIDs(ctx)
	if err != nil {
		return nil, err
	}
	var protoIDs []*StreamIDFullyQualifiedProto
	for _, id := range ids {
		protoIDs = append(protoIDs, streamIDToProto(id))
	}
	return &GetActiveStreamIDsReply{StreamIds: protoIDs}, nil
}

// StartStream starts a stream on a platform with a profile.
func (s *wingOutService) StartStream(ctx context.Context, req *StartStreamRequest) (*StartStreamReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().StartStream(ctx, req.GetPlatformId(), req.GetProfileName()); err != nil {
		return nil, err
	}
	return &StartStreamReply{}, nil
}

// EndStream ends a stream on a platform.
func (s *wingOutService) EndStream(ctx context.Context, req *EndStreamRequest) (*EndStreamReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().EndStream(ctx, req.GetPlatformId()); err != nil {
		return nil, err
	}
	return &EndStreamReply{}, nil
}

// SubscribeToStreamsChanges streams stream changes to the client.
func (s *wingOutService) SubscribeToStreamsChanges(req *SubscribeToStreamsChangesRequest, stream grpc.ServerStreamingServer[StreamChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamsChanges(stream.Context())
	if err != nil {
		return err
	}
	for st := range ch {
		if err := stream.Send(&StreamChangeEvent{
			Stream: streamInfoToProto(&st),
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Accounts & Platforms ---

// GetAccounts returns accounts for the given platform IDs.
func (s *wingOutService) GetAccounts(ctx context.Context, req *GetAccountsRequest) (*GetAccountsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	accounts, err := s.getStreamD().GetAccounts(ctx, nil)
	if err != nil {
		return nil, err
	}
	var protoAccounts []*AccountInfoProto
	for _, a := range accounts {
		protoAccounts = append(protoAccounts, &AccountInfoProto{
			PlatformId: a.PlatformID,
			AccountId:  a.AccountID,
		})
	}
	return &GetAccountsReply{Accounts: protoAccounts}, nil
}

// IsBackendEnabled checks if a backend platform is enabled.
func (s *wingOutService) IsBackendEnabled(ctx context.Context, req *IsBackendEnabledRequest) (*IsBackendEnabledReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	enabled, err := s.getStreamD().IsBackendEnabled(ctx, req.GetPlatformId())
	if err != nil {
		return nil, err
	}
	return &IsBackendEnabledReply{Enabled: enabled}, nil
}

// GetBackendInfo returns information about a backend platform.
func (s *wingOutService) GetBackendInfo(ctx context.Context, req *GetBackendInfoRequest) (*GetBackendInfoReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	info, err := s.getStreamD().GetBackendInfo(ctx, req.GetPlatformId())
	if err != nil {
		return nil, err
	}
	return &GetBackendInfoReply{
		PlatformId: info.PlatformID,
	}, nil
}

// GetPlatforms returns all available platform IDs.
func (s *wingOutService) GetPlatforms(ctx context.Context, req *GetPlatformsRequest) (*GetPlatformsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	platforms, err := s.getStreamD().GetPlatforms(ctx)
	if err != nil {
		return nil, err
	}
	return &GetPlatformsReply{PlatformIds: platforms}, nil
}

// --- StreamD: Metadata ---

// SetTitle sets the title for a platform stream.
func (s *wingOutService) SetTitle(ctx context.Context, req *SetTitleRequest) (*SetTitleReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SetTitle(ctx, req.GetPlatformId(), req.GetTitle()); err != nil {
		return nil, err
	}
	return &SetTitleReply{}, nil
}

// SetDescription sets the description for a platform stream.
func (s *wingOutService) SetDescription(ctx context.Context, req *SetDescriptionRequest) (*SetDescriptionReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SetDescription(ctx, req.GetPlatformId(), req.GetDescription()); err != nil {
		return nil, err
	}
	return &SetDescriptionReply{}, nil
}

// --- StreamD: Profiles ---

// ApplyProfile applies a profile to a stream.
func (s *wingOutService) ApplyProfile(ctx context.Context, req *ApplyProfileRequest) (*ApplyProfileReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().ApplyProfile(ctx, backend.StreamIDFullyQualified{}, req.GetProfileName()); err != nil {
		return nil, err
	}
	return &ApplyProfileReply{}, nil
}

// --- StreamD: Variables ---

// GetVariable returns a variable value by key.
func (s *wingOutService) GetVariable(ctx context.Context, req *GetVariableRequest) (*GetVariableReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	value, err := s.getStreamD().GetVariable(ctx, req.GetKey())
	if err != nil {
		return nil, err
	}
	return &GetVariableReply{Value: value}, nil
}

// GetVariableHash returns the hash of a variable value.
func (s *wingOutService) GetVariableHash(ctx context.Context, req *GetVariableHashRequest) (*GetVariableHashReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	hash, err := s.getStreamD().GetVariableHash(ctx, req.GetKey(), req.GetHashType().String())
	if err != nil {
		return nil, err
	}
	return &GetVariableHashReply{Hash: hash}, nil
}

// SetVariable sets a variable value by key.
func (s *wingOutService) SetVariable(ctx context.Context, req *SetVariableRequest) (*SetVariableReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SetVariable(ctx, req.GetKey(), req.GetValue()); err != nil {
		return nil, err
	}
	return &SetVariableReply{}, nil
}

// SubscribeToVariable streams variable changes to the client.
func (s *wingOutService) SubscribeToVariable(req *SubscribeToVariableRequest, stream grpc.ServerStreamingServer[VariableChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToVariable(stream.Context(), req.GetKey())
	if err != nil {
		return err
	}
	for value := range ch {
		if err := stream.Send(&VariableChangeEvent{
			Key:   req.GetKey(),
			Value: value,
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: OAuth ---

// SubscribeToOAuthRequests streams OAuth requests to the client.
func (s *wingOutService) SubscribeToOAuthRequests(req *SubscribeToOAuthRequestsRequest, stream grpc.ServerStreamingServer[OAuthRequestEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToOAuthRequests(stream.Context())
	if err != nil {
		return err
	}
	for oauthReq := range ch {
		if err := stream.Send(&OAuthRequestEvent{
			RequestId:  oauthReq.RequestID,
			AuthUrl:    oauthReq.AuthURL,
			PlatformId: oauthReq.PlatformID,
		}); err != nil {
			return err
		}
	}
	return nil
}

// SubmitOAuthCode submits an OAuth authorization code for a request.
func (s *wingOutService) SubmitOAuthCode(ctx context.Context, req *SubmitOAuthCodeRequest) (*SubmitOAuthCodeReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SubmitOAuthCode(ctx, req.GetRequestId(), req.GetCode()); err != nil {
		return nil, err
	}
	return &SubmitOAuthCodeReply{}, nil
}

// --- StreamD: Stream Servers ---

// StartStreamServer starts a stream server with the given config.
func (s *wingOutService) StartStreamServer(ctx context.Context, req *StartStreamServerRequest) (*StartStreamServerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	config := backend.StreamServer{
		Type:       req.GetServerType().String(),
		ListenAddr: req.GetListenAddr(),
	}
	if err := s.getStreamD().StartStreamServer(ctx, config); err != nil {
		return nil, err
	}
	return &StartStreamServerReply{}, nil
}

// StopStreamServer stops a stream server by ID.
func (s *wingOutService) StopStreamServer(ctx context.Context, req *StopStreamServerRequest) (*StopStreamServerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().StopStreamServer(ctx, req.GetServerId()); err != nil {
		return nil, err
	}
	return &StopStreamServerReply{}, nil
}

// SubscribeToStreamServersChanges streams stream server changes to the client.
func (s *wingOutService) SubscribeToStreamServersChanges(req *SubscribeToStreamServersChangesRequest, stream grpc.ServerStreamingServer[StreamServerChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamServersChanges(stream.Context())
	if err != nil {
		return err
	}
	for srv := range ch {
		if err := stream.Send(&StreamServerChangeEvent{
			Server: &StreamServerProto{
				Id:         srv.ID,
				Type:       srv.Type,
				ListenAddr: srv.ListenAddr,
			},
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Stream Sources ---

// ListStreamSources returns all stream sources.
func (s *wingOutService) ListStreamSources(ctx context.Context, req *ListStreamSourcesRequest) (*ListStreamSourcesReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	sources, err := s.getStreamD().ListStreamSources(ctx)
	if err != nil {
		return nil, err
	}
	var protoSources []*StreamSourceProto
	for _, src := range sources {
		protoSources = append(protoSources, streamSourceToProto(&src))
	}
	return &ListStreamSourcesReply{Sources: protoSources}, nil
}

// AddStreamSource adds a new stream source.
func (s *wingOutService) AddStreamSource(ctx context.Context, req *AddStreamSourceRequest) (*AddStreamSourceReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().AddStreamSource(ctx, req.GetUrl()); err != nil {
		return nil, err
	}
	return &AddStreamSourceReply{}, nil
}

// RemoveStreamSource removes a stream source.
func (s *wingOutService) RemoveStreamSource(ctx context.Context, req *RemoveStreamSourceRequest) (*RemoveStreamSourceReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveStreamSource(ctx, req.GetSourceId()); err != nil {
		return nil, err
	}
	return &RemoveStreamSourceReply{}, nil
}

// SubscribeToStreamSourcesChanges streams stream source changes to the client.
func (s *wingOutService) SubscribeToStreamSourcesChanges(req *SubscribeToStreamSourcesChangesRequest, stream grpc.ServerStreamingServer[StreamSourceChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamSourcesChanges(stream.Context())
	if err != nil {
		return err
	}
	for src := range ch {
		if err := stream.Send(&StreamSourceChangeEvent{
			Source: streamSourceToProto(&src),
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Stream Sinks ---

// ListStreamSinks returns all stream sinks.
func (s *wingOutService) ListStreamSinks(ctx context.Context, req *ListStreamSinksRequest) (*ListStreamSinksReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	sinks, err := s.getStreamD().ListStreamSinks(ctx)
	if err != nil {
		return nil, err
	}
	var protoSinks []*StreamSinkProto
	for _, sink := range sinks {
		protoSinks = append(protoSinks, streamSinkToProto(&sink))
	}
	return &ListStreamSinksReply{Sinks: protoSinks}, nil
}

// AddStreamSink adds a new stream sink.
func (s *wingOutService) AddStreamSink(ctx context.Context, req *AddStreamSinkRequest) (*AddStreamSinkReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	sink := streamSinkFromProtoRequest(req)
	if err := s.getStreamD().AddStreamSink(ctx, sink); err != nil {
		return nil, err
	}
	return &AddStreamSinkReply{}, nil
}

// UpdateStreamSink updates an existing stream sink.
func (s *wingOutService) UpdateStreamSink(ctx context.Context, req *UpdateStreamSinkRequest) (*UpdateStreamSinkReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	sink := backend.StreamSink{
		ID:   req.GetSinkId(),
		Type: req.GetSinkType().String(),
		URL:  req.GetUrl(),
	}
	if ec := req.GetEncoderConfig(); ec != nil {
		sink.EncoderConfig = encoderConfigFromProto(ec)
	}
	if err := s.getStreamD().UpdateStreamSink(ctx, sink); err != nil {
		return nil, err
	}
	return &UpdateStreamSinkReply{}, nil
}

// GetStreamSinkConfig returns the configuration for a stream sink.
func (s *wingOutService) GetStreamSinkConfig(ctx context.Context, req *GetStreamSinkConfigRequest) (*GetStreamSinkConfigReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	cfg, err := s.getStreamD().GetStreamSinkConfig(ctx, req.GetSinkId())
	if err != nil {
		return nil, err
	}
	reply := &GetStreamSinkConfigReply{
		Config: &StreamSinkConfigProto{
			Url: cfg.URL,
		},
	}
	if cfg.EncoderConfig != nil {
		reply.Config.Encoder = encoderConfigToProto(cfg.EncoderConfig)
	}
	return reply, nil
}

// RemoveStreamSink removes a stream sink.
func (s *wingOutService) RemoveStreamSink(ctx context.Context, req *RemoveStreamSinkRequest) (*RemoveStreamSinkReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveStreamSink(ctx, req.GetSinkId()); err != nil {
		return nil, err
	}
	return &RemoveStreamSinkReply{}, nil
}

// SubscribeToStreamSinksChanges streams stream sink changes to the client.
func (s *wingOutService) SubscribeToStreamSinksChanges(req *SubscribeToStreamSinksChangesRequest, stream grpc.ServerStreamingServer[StreamSinkChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamSinksChanges(stream.Context())
	if err != nil {
		return err
	}
	for sink := range ch {
		if err := stream.Send(&StreamSinkChangeEvent{
			Sink: streamSinkToProto(&sink),
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Stream Forwards ---

// AddStreamForward adds a new stream forward.
func (s *wingOutService) AddStreamForward(ctx context.Context, req *AddStreamForwardRequest) (*AddStreamForwardReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	fwd := backend.StreamForward{
		SourceID: req.GetSourceId(),
		SinkID:   req.GetSinkId(),
		Enabled:  req.GetEnabled(),
	}
	if q := req.GetQuirks(); q != nil {
		fwd.Quirks = streamForwardQuirksFromProto(q)
	}
	if err := s.getStreamD().AddStreamForward(ctx, fwd); err != nil {
		return nil, err
	}
	return &AddStreamForwardReply{}, nil
}

// UpdateStreamForward updates an existing stream forward.
func (s *wingOutService) UpdateStreamForward(ctx context.Context, req *UpdateStreamForwardRequest) (*UpdateStreamForwardReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	fwd := backend.StreamForward{
		SourceID: req.GetSourceId(),
		SinkID:   req.GetSinkId(),
		Enabled:  req.GetEnabled(),
	}
	if q := req.GetQuirks(); q != nil {
		fwd.Quirks = streamForwardQuirksFromProto(q)
	}
	if err := s.getStreamD().UpdateStreamForward(ctx, fwd); err != nil {
		return nil, err
	}
	return &UpdateStreamForwardReply{}, nil
}

// RemoveStreamForward removes a stream forward.
func (s *wingOutService) RemoveStreamForward(ctx context.Context, req *RemoveStreamForwardRequest) (*RemoveStreamForwardReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveStreamForward(ctx, req.GetSourceId(), req.GetSinkId()); err != nil {
		return nil, err
	}
	return &RemoveStreamForwardReply{}, nil
}

// SubscribeToStreamForwardsChanges streams stream forward changes to the client.
func (s *wingOutService) SubscribeToStreamForwardsChanges(req *SubscribeToStreamForwardsChangesRequest, stream grpc.ServerStreamingServer[StreamForwardChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamForwardsChanges(stream.Context())
	if err != nil {
		return err
	}
	for fwd := range ch {
		if err := stream.Send(&StreamForwardChangeEvent{
			Forward: &StreamForwardProto{
				SourceId: fwd.SourceID,
				SinkId:   fwd.SinkID,
				SinkType: fwd.SinkType,
				Enabled:  fwd.Enabled,
			},
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Stream Publisher ---

// WaitForStreamPublisher blocks until a stream publisher connects for the given source.
func (s *wingOutService) WaitForStreamPublisher(ctx context.Context, req *WaitForStreamPublisherRequest) (*WaitForStreamPublisherReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().WaitForStreamPublisher(ctx, req.GetSourceId()); err != nil {
		return nil, err
	}
	return &WaitForStreamPublisherReply{}, nil
}

// --- StreamD: Stream Players CRUD ---

// AddStreamPlayer adds a new stream player.
func (s *wingOutService) AddStreamPlayer(ctx context.Context, req *AddStreamPlayerRequest) (*AddStreamPlayerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	player := streamPlayerFromProto(req.GetPlayer())
	if err := s.getStreamD().AddStreamPlayer(ctx, player); err != nil {
		return nil, err
	}
	return &AddStreamPlayerReply{}, nil
}

// RemoveStreamPlayer removes a stream player.
func (s *wingOutService) RemoveStreamPlayer(ctx context.Context, req *RemoveStreamPlayerRequest) (*RemoveStreamPlayerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveStreamPlayer(ctx, req.GetPlayerId()); err != nil {
		return nil, err
	}
	return &RemoveStreamPlayerReply{}, nil
}

// UpdateStreamPlayer updates an existing stream player.
func (s *wingOutService) UpdateStreamPlayer(ctx context.Context, req *UpdateStreamPlayerRequest) (*UpdateStreamPlayerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	player := streamPlayerFromProto(req.GetPlayer())
	if err := s.getStreamD().UpdateStreamPlayer(ctx, player); err != nil {
		return nil, err
	}
	return &UpdateStreamPlayerReply{}, nil
}

// GetStreamPlayer returns a stream player by ID.
func (s *wingOutService) GetStreamPlayer(ctx context.Context, req *GetStreamPlayerRequest) (*GetStreamPlayerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	player, err := s.getStreamD().GetStreamPlayer(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &GetStreamPlayerReply{
		Player: &StreamPlayerProto{
			Id:       player.ID,
			Title:    player.Title,
			Link:     player.Link,
			Position: player.Position,
			Length:   player.Length,
			IsPaused: player.IsPaused,
		},
	}, nil
}

// SubscribeToStreamPlayersChanges streams stream player changes to the client.
func (s *wingOutService) SubscribeToStreamPlayersChanges(req *SubscribeToStreamPlayersChangesRequest, stream grpc.ServerStreamingServer[StreamPlayerChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToStreamPlayersChanges(stream.Context())
	if err != nil {
		return err
	}
	for p := range ch {
		if err := stream.Send(&StreamPlayerChangeEvent{
			Player: &StreamPlayerProto{
				Id:       p.ID,
				Title:    p.Title,
				Link:     p.Link,
				Position: p.Position,
				Length:   p.Length,
				IsPaused: p.IsPaused,
			},
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- StreamD: Player Control ---

// StreamPlayerOpen opens a URL in a player.
func (s *wingOutService) StreamPlayerOpen(ctx context.Context, req *StreamPlayerOpenRequest) (*StreamPlayerOpenReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().PlayerOpen(ctx, req.GetPlayerId(), req.GetUrl()); err != nil {
		return nil, err
	}
	return &StreamPlayerOpenReply{}, nil
}

// StreamPlayerProcessTitle processes a title for a player and returns the result.
func (s *wingOutService) StreamPlayerProcessTitle(ctx context.Context, req *StreamPlayerProcessTitleRequest) (*StreamPlayerProcessTitleReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	_, err := s.getStreamD().PlayerProcessTitle(ctx, req.GetPlayerId(), req.GetTitle())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerProcessTitleReply{}, nil
}

// StreamPlayerGetLink returns the current link for a player.
func (s *wingOutService) StreamPlayerGetLink(ctx context.Context, req *StreamPlayerGetLinkRequest) (*StreamPlayerGetLinkReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	link, err := s.getStreamD().PlayerGetLink(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerGetLinkReply{Url: link}, nil
}

// StreamPlayerEndChan streams an event when a player finishes.
func (s *wingOutService) StreamPlayerEndChan(req *StreamPlayerEndChanRequest, stream grpc.ServerStreamingServer[StreamPlayerEndEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().PlayerEndChan(stream.Context(), req.GetPlayerId())
	if err != nil {
		return err
	}
	<-ch
	if err := stream.Send(&StreamPlayerEndEvent{
		PlayerId: req.GetPlayerId(),
	}); err != nil {
		return err
	}
	return nil
}

// StreamPlayerIsEnded checks if a player has finished playback.
func (s *wingOutService) StreamPlayerIsEnded(ctx context.Context, req *StreamPlayerIsEndedRequest) (*StreamPlayerIsEndedReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	ended, err := s.getStreamD().PlayerIsEnded(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerIsEndedReply{IsEnded: ended}, nil
}

// StreamPlayerGetPosition returns the current position in seconds.
func (s *wingOutService) StreamPlayerGetPosition(ctx context.Context, req *StreamPlayerGetPositionRequest) (*StreamPlayerGetPositionReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	pos, err := s.getStreamD().PlayerGetPosition(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerGetPositionReply{Seconds: pos}, nil
}

// StreamPlayerGetLength returns the total length in seconds.
func (s *wingOutService) StreamPlayerGetLength(ctx context.Context, req *StreamPlayerGetLengthRequest) (*StreamPlayerGetLengthReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	length, err := s.getStreamD().PlayerGetLength(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerGetLengthReply{Seconds: length}, nil
}

// StreamPlayerGetLag returns player lag in seconds.
func (s *wingOutService) StreamPlayerGetLag(ctx context.Context, req *StreamPlayerGetLagRequest) (*StreamPlayerGetLagReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	lag, err := s.getStreamD().PlayerGetLag(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerGetLagReply{Seconds: lag}, nil
}

// StreamPlayerSetSpeed sets the playback speed.
func (s *wingOutService) StreamPlayerSetSpeed(ctx context.Context, req *StreamPlayerSetSpeedRequest) (*StreamPlayerSetSpeedReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().PlayerSetSpeed(ctx, req.GetPlayerId(), req.GetSpeed()); err != nil {
		return nil, err
	}
	return &StreamPlayerSetSpeedReply{}, nil
}

// StreamPlayerGetSpeed returns the current playback speed.
func (s *wingOutService) StreamPlayerGetSpeed(ctx context.Context, req *StreamPlayerGetSpeedRequest) (*StreamPlayerGetSpeedReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	speed, err := s.getStreamD().PlayerGetSpeed(ctx, req.GetPlayerId())
	if err != nil {
		return nil, err
	}
	return &StreamPlayerGetSpeedReply{Speed: speed}, nil
}

// StreamPlayerSetPause sets the pause state of a player.
func (s *wingOutService) StreamPlayerSetPause(ctx context.Context, req *StreamPlayerSetPauseRequest) (*StreamPlayerSetPauseReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().PlayerSetPause(ctx, req.GetPlayerId(), req.GetPaused()); err != nil {
		return nil, err
	}
	return &StreamPlayerSetPauseReply{}, nil
}

// StreamPlayerStop stops a player.
func (s *wingOutService) StreamPlayerStop(ctx context.Context, req *StreamPlayerStopRequest) (*StreamPlayerStopReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().PlayerStop(ctx, req.GetPlayerId()); err != nil {
		return nil, err
	}
	return &StreamPlayerStopReply{}, nil
}

// StreamPlayerClose closes a player.
func (s *wingOutService) StreamPlayerClose(ctx context.Context, req *StreamPlayerCloseRequest) (*StreamPlayerCloseReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().PlayerClose(ctx, req.GetPlayerId()); err != nil {
		return nil, err
	}
	return &StreamPlayerCloseReply{}, nil
}

// --- StreamD: Timers ---

// AddTimer adds a new timer.
func (s *wingOutService) AddTimer(ctx context.Context, req *AddTimerRequest) (*AddTimerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	timer := timerFromProto(req.GetTimer())
	if err := s.getStreamD().AddTimer(ctx, timer); err != nil {
		return nil, err
	}
	return &AddTimerReply{}, nil
}

// RemoveTimer removes a timer by ID.
func (s *wingOutService) RemoveTimer(ctx context.Context, req *RemoveTimerRequest) (*RemoveTimerReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveTimer(ctx, req.GetTimerId()); err != nil {
		return nil, err
	}
	return &RemoveTimerReply{}, nil
}

// ListTimers returns all timers.
func (s *wingOutService) ListTimers(ctx context.Context, req *ListTimersRequest) (*ListTimersReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	timers, err := s.getStreamD().ListTimers(ctx)
	if err != nil {
		return nil, err
	}
	var protoTimers []*TimerProto
	for _, t := range timers {
		protoTimers = append(protoTimers, timerToProto(&t))
	}
	return &ListTimersReply{Timers: protoTimers}, nil
}

// --- StreamD: Trigger Rules ---

// ListTriggerRules returns all trigger rules.
func (s *wingOutService) ListTriggerRules(ctx context.Context, req *ListTriggerRulesRequest) (*ListTriggerRulesReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	rules, err := s.getStreamD().ListTriggerRules(ctx)
	if err != nil {
		return nil, err
	}
	var protoRules []*TriggerRuleProto
	for _, r := range rules {
		protoRules = append(protoRules, triggerRuleToProto(&r))
	}
	return &ListTriggerRulesReply{Rules: protoRules}, nil
}

// AddTriggerRule adds a new trigger rule.
func (s *wingOutService) AddTriggerRule(ctx context.Context, req *AddTriggerRuleRequest) (*AddTriggerRuleReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	rule := triggerRuleFromProto(req.GetRule())
	if err := s.getStreamD().AddTriggerRule(ctx, rule); err != nil {
		return nil, err
	}
	return &AddTriggerRuleReply{}, nil
}

// RemoveTriggerRule removes a trigger rule by ID.
func (s *wingOutService) RemoveTriggerRule(ctx context.Context, req *RemoveTriggerRuleRequest) (*RemoveTriggerRuleReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveTriggerRule(ctx, req.GetRuleId()); err != nil {
		return nil, err
	}
	return &RemoveTriggerRuleReply{}, nil
}

// UpdateTriggerRule updates an existing trigger rule.
func (s *wingOutService) UpdateTriggerRule(ctx context.Context, req *UpdateTriggerRuleRequest) (*UpdateTriggerRuleReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	rule := triggerRuleFromProto(req.GetRule())
	if err := s.getStreamD().UpdateTriggerRule(ctx, rule); err != nil {
		return nil, err
	}
	return &UpdateTriggerRuleReply{}, nil
}

// --- StreamD: Events ---

// SubmitEvent submits a generic event.
func (s *wingOutService) SubmitEvent(ctx context.Context, req *SubmitEventRequest) (*SubmitEventReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	ev := req.GetEvent()
	if err := s.getStreamD().SubmitEvent(ctx, backend.Event{
		Type: ev.GetType().String(),
		Data: ev.GetData(),
	}); err != nil {
		return nil, err
	}
	return &SubmitEventReply{}, nil
}

// --- StreamD: Chat ---

// SendChatMessage sends a chat message to a platform.
func (s *wingOutService) SendChatMessage(ctx context.Context, req *SendChatMessageRequest) (*SendChatMessageReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().SendChatMessage(ctx, req.GetPlatformId(), "", req.GetMessage()); err != nil {
		return nil, err
	}
	return &SendChatMessageReply{}, nil
}

// InjectPlatformEvent injects a platform chat event.
func (s *wingOutService) InjectPlatformEvent(ctx context.Context, req *InjectPlatformEventRequest) (*InjectPlatformEventReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	event := chatEventFromProto(req.GetEvent())
	if err := s.getStreamD().InjectPlatformEvent(ctx, event); err != nil {
		return nil, err
	}
	return &InjectPlatformEventReply{}, nil
}

// RemoveChatMessage removes a chat message from a platform.
func (s *wingOutService) RemoveChatMessage(ctx context.Context, req *RemoveChatMessageRequest) (*RemoveChatMessageReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RemoveChatMessage(ctx, req.GetPlatformId(), req.GetMessageId()); err != nil {
		return nil, err
	}
	return &RemoveChatMessageReply{}, nil
}

// BanUser bans a user on a platform.
func (s *wingOutService) BanUser(ctx context.Context, req *BanUserRequest) (*BanUserReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().BanUser(ctx, req.GetPlatformId(), req.GetUserId(), req.GetReason(), int64(req.GetDurationSeconds())); err != nil {
		return nil, err
	}
	return &BanUserReply{}, nil
}

// --- StreamD: Social ---

// Shoutout sends a shoutout on a platform.
func (s *wingOutService) Shoutout(ctx context.Context, req *ShoutoutRequest) (*ShoutoutReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().Shoutout(ctx, req.GetPlatformId(), req.GetTargetUserName()); err != nil {
		return nil, err
	}
	return &ShoutoutReply{}, nil
}

// RaidTo starts a raid to a target channel.
func (s *wingOutService) RaidTo(ctx context.Context, req *RaidToRequest) (*RaidToReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().RaidTo(ctx, req.GetPlatformId(), req.GetTargetChannel()); err != nil {
		return nil, err
	}
	return &RaidToReply{}, nil
}

// GetPeerIDs returns the list of peer IDs.
func (s *wingOutService) GetPeerIDs(ctx context.Context, req *GetPeerIDsRequest) (*GetPeerIDsReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	ids, err := s.getStreamD().GetPeerIDs(ctx)
	if err != nil {
		return nil, err
	}
	return &GetPeerIDsReply{PeerIds: ids}, nil
}

// --- StreamD: AI ---

// LLMGenerate generates text using an LLM.
func (s *wingOutService) LLMGenerate(ctx context.Context, req *LLMGenerateRequest) (*LLMGenerateReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	result, err := s.getStreamD().LLMGenerate(ctx, req.GetPrompt())
	if err != nil {
		return nil, err
	}
	return &LLMGenerateReply{Text: result}, nil
}

// --- StreamD: System ---

// Restart restarts the StreamD backend.
func (s *wingOutService) Restart(ctx context.Context, req *RestartRequest) (*RestartReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().Restart(ctx); err != nil {
		return nil, err
	}
	return &RestartReply{}, nil
}

// EXPERIMENTAL_ReinitStreamControllers reinitializes all stream controllers.
func (s *wingOutService) EXPERIMENTAL_ReinitStreamControllers(ctx context.Context, req *ReinitStreamControllersRequest) (*ReinitStreamControllersReply, error) {
	if err := s.requireStreamD(); err != nil {
		return nil, err
	}
	if err := s.getStreamD().ReinitStreamControllers(ctx); err != nil {
		return nil, err
	}
	return &ReinitStreamControllersReply{}, nil
}

// SubscribeToConfigChanges streams config changes to the client.
func (s *wingOutService) SubscribeToConfigChanges(req *SubscribeToConfigChangesRequest, stream grpc.ServerStreamingServer[ConfigChangeEvent]) error {
	if err := s.requireStreamD(); err != nil {
		return err
	}
	ch, err := s.getStreamD().SubscribeToConfigChanges(stream.Context())
	if err != nil {
		return err
	}
	for cfg := range ch {
		if err := stream.Send(&ConfigChangeEvent{
			Config: cfg,
		}); err != nil {
			return err
		}
	}
	return nil
}

// --- FFStream: Extended ---

// FFSetLoggingLevel sets the FFmpeg-specific logging level.
func (s *wingOutService) FFSetLoggingLevel(ctx context.Context, req *FFSetLoggingLevelRequest) (*FFSetLoggingLevelReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	if err := s.getFFStream().FFSetLoggingLevel(ctx, int(req.GetLevel())); err != nil {
		return nil, err
	}
	return &FFSetLoggingLevelReply{}, nil
}

// RemoveOutput removes an output by ID.
func (s *wingOutService) RemoveOutput(ctx context.Context, req *RemoveOutputRequest) (*RemoveOutputReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	id, err := strconv.ParseUint(req.GetOutputId(), 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid output_id: %w", err)
	}
	if err := s.getFFStream().RemoveOutput(ctx, id); err != nil {
		return nil, err
	}
	return &RemoveOutputReply{}, nil
}

// GetCurrentOutput returns the current output configuration.
func (s *wingOutService) GetCurrentOutput(ctx context.Context, req *GetCurrentOutputRequest) (*GetCurrentOutputReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	output, err := s.getFFStream().GetCurrentOutput(ctx)
	if err != nil {
		return nil, err
	}
	return &GetCurrentOutputReply{
		Output: currentOutputToProto(output),
	}, nil
}

// SwitchOutputByProps dynamically switches output encoding properties.
func (s *wingOutService) SwitchOutputByProps(ctx context.Context, req *SwitchOutputByPropsRequest) (*SwitchOutputByPropsReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	props := senderPropsFromProto(req.GetProps())
	if err := s.getFFStream().SwitchOutputByProps(ctx, props); err != nil {
		return nil, err
	}
	return &SwitchOutputByPropsReply{}, nil
}

// GetOutputSRTStats returns SRT protocol statistics.
func (s *wingOutService) GetOutputSRTStats(ctx context.Context, req *GetOutputSRTStatsRequest) (*GetOutputSRTStatsReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	// The proto request has no output_id field, pass 0 as default.
	stats, err := s.getFFStream().GetOutputSRTStats(ctx, 0)
	if err != nil {
		return nil, err
	}
	return &GetOutputSRTStatsReply{
		Stats: srtStatsToProto(stats),
	}, nil
}

// GetSRTFlagInt returns the value of an SRT integer flag.
func (s *wingOutService) GetSRTFlagInt(ctx context.Context, req *GetSRTFlagIntRequest) (*GetSRTFlagIntReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	value, err := s.getFFStream().GetSRTFlagInt(ctx, backend.SRTFlagInt(req.GetFlag()))
	if err != nil {
		return nil, err
	}
	return &GetSRTFlagIntReply{Value: value}, nil
}

// SetSRTFlagInt sets the value of an SRT integer flag.
func (s *wingOutService) SetSRTFlagInt(ctx context.Context, req *SetSRTFlagIntRequest) (*SetSRTFlagIntReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	if err := s.getFFStream().SetSRTFlagInt(ctx, backend.SRTFlagInt(req.GetFlag()), req.GetValue()); err != nil {
		return nil, err
	}
	return &SetSRTFlagIntReply{}, nil
}

// FFWaitChan streams an event when the FFStream engine finishes.
func (s *wingOutService) FFWaitChan(req *FFWaitChanRequest, stream grpc.ServerStreamingServer[FFWaitEvent]) error {
	if err := s.requireFFStream(); err != nil {
		return err
	}
	ch, err := s.getFFStream().WaitChan(stream.Context())
	if err != nil {
		return err
	}
	<-ch
	if err := stream.Send(&FFWaitEvent{}); err != nil {
		return err
	}
	return nil
}

// FFEnd terminates the streaming engine.
func (s *wingOutService) FFEnd(ctx context.Context, req *FFEndRequest) (*FFEndReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	if err := s.getFFStream().End(ctx); err != nil {
		return nil, err
	}
	return &FFEndReply{}, nil
}

// GetPipelines returns all pipelines.
func (s *wingOutService) GetPipelines(ctx context.Context, req *GetPipelinesRequest) (*GetPipelinesReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	pipelines, err := s.getFFStream().GetPipelines(ctx)
	if err != nil {
		return nil, err
	}
	var protoPipelines []*PipelineProto
	for _, p := range pipelines {
		protoPipelines = append(protoPipelines, &PipelineProto{
			Id:          p.ID,
			Description: p.Description,
		})
	}
	return &GetPipelinesReply{Pipelines: protoPipelines}, nil
}

// GetVideoAutoBitRateConfig returns the current auto-bitrate config.
func (s *wingOutService) GetVideoAutoBitRateConfig(ctx context.Context, req *GetVideoAutoBitRateConfigRequest) (*GetVideoAutoBitRateConfigReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	cfg, err := s.getFFStream().GetAutoBitRateVideoConfig(ctx)
	if err != nil {
		return nil, err
	}
	return &GetVideoAutoBitRateConfigReply{
		Config: autoBitRateVideoConfigToProto(cfg),
	}, nil
}

// SetVideoAutoBitRateConfig configures auto-bitrate for video.
func (s *wingOutService) SetVideoAutoBitRateConfig(ctx context.Context, req *SetVideoAutoBitRateConfigRequest) (*SetVideoAutoBitRateConfigReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	cfg := autoBitRateVideoConfigFromProto(req.GetConfig())
	if err := s.getFFStream().SetAutoBitRateVideoConfig(ctx, cfg); err != nil {
		return nil, err
	}
	return &SetVideoAutoBitRateConfigReply{}, nil
}

// GetVideoAutoBitRateCalculator returns the video auto bitrate calculator config.
func (s *wingOutService) GetVideoAutoBitRateCalculator(ctx context.Context, req *GetVideoAutoBitRateCalculatorRequest) (*GetVideoAutoBitRateCalculatorReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	config, err := s.getFFStream().GetVideoAutoBitRateCalculator(ctx)
	if err != nil {
		return nil, err
	}
	return &GetVideoAutoBitRateCalculatorReply{
		Calculator: &AutoBitRateCalculatorProto{
			Config: config,
		},
	}, nil
}

// SetVideoAutoBitRateCalculator sets the video auto bitrate calculator config.
func (s *wingOutService) SetVideoAutoBitRateCalculator(ctx context.Context, req *SetVideoAutoBitRateCalculatorRequest) (*SetVideoAutoBitRateCalculatorReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	calc := req.GetCalculator()
	var config []byte
	if calc != nil {
		config = calc.GetConfig()
	}
	if err := s.getFFStream().SetVideoAutoBitRateCalculator(ctx, config); err != nil {
		return nil, err
	}
	return &SetVideoAutoBitRateCalculatorReply{}, nil
}

// FFMonitor starts monitoring pipeline events.
func (s *wingOutService) FFMonitor(req *FFMonitorRequest, stream grpc.ServerStreamingServer[FFMonitorEvent]) error {
	if err := s.requireFFStream(); err != nil {
		return err
	}
	ch, err := s.getFFStream().Monitor(stream.Context(), backend.MonitorRequest{})
	if err != nil {
		return err
	}
	for ev := range ch {
		if err := stream.Send(&FFMonitorEvent{
			EventType: ev.EventType,
			Timestamp: ev.Timestamp,
		}); err != nil {
			return err
		}
	}
	return nil
}

// GetInputsInfo returns information about all inputs.
func (s *wingOutService) GetInputsInfo(ctx context.Context, req *GetInputsInfoRequest) (*GetInputsInfoReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	inputs, err := s.getFFStream().GetInputsInfo(ctx)
	if err != nil {
		return nil, err
	}
	var protoInputs []*InputInfoProto
	for _, inp := range inputs {
		protoInputs = append(protoInputs, inputInfoToProto(&inp))
	}
	return &GetInputsInfoReply{Inputs: protoInputs}, nil
}

// SetInputCustomOption sets a custom option on an input.
func (s *wingOutService) SetInputCustomOption(ctx context.Context, req *SetInputCustomOptionRequest) (*SetInputCustomOptionReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	opt := req.GetOption()
	if err := s.getFFStream().SetInputCustomOption(ctx, req.GetInputId(), opt.GetKey(), opt.GetValue()); err != nil {
		return nil, err
	}
	return &SetInputCustomOptionReply{}, nil
}

// SetStopInput stops a specific input.
func (s *wingOutService) SetStopInput(ctx context.Context, req *SetStopInputRequest) (*SetStopInputReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	if err := s.getFFStream().SetStopInput(ctx, req.GetInputId()); err != nil {
		return nil, err
	}
	return &SetStopInputReply{}, nil
}

// InjectDiagnostics injects diagnostics data.
func (s *wingOutService) InjectDiagnostics(ctx context.Context, req *InjectDiagnosticsRequest) (*InjectDiagnosticsReply, error) {
	if err := s.requireFFStream(); err != nil {
		return nil, err
	}
	diag := diagnosticsFromProto(req.GetDiagnostics())
	if err := s.getFFStream().InjectDiagnostics(ctx, diag, 0); err != nil {
		return nil, err
	}
	return &InjectDiagnosticsReply{}, nil
}

// --- Conversion helpers ---

func bitRateInfoToProto(b *backend.BitRateInfo) *BitRateInfoProto {
	if b == nil {
		return nil
	}
	return &BitRateInfoProto{
		Audio: b.Audio,
		Video: b.Video,
		Other: b.Other,
	}
}

func trackLatenciesToProto(t *backend.TrackLatencies) *TrackLatenciesProto {
	if t == nil {
		return nil
	}
	return &TrackLatenciesProto{
		PreTranscodingUs:    t.PreTranscodingUs,
		TranscodingUs:       t.TranscodingUs,
		TranscodedPreSendUs: t.TranscodedPreSendUs,
		SendingUs:           t.SendingUs,
	}
}

func streamQualityToProto(q *backend.StreamQuality) *StreamQualityProto {
	if q == nil {
		return nil
	}
	return &StreamQualityProto{
		Continuity: q.Continuity,
		Overlap:    q.Overlap,
		FrameRate:  q.FrameRate,
		InvalidDts: q.InvalidDTS,
	}
}

func streamIDToProto(id backend.StreamIDFullyQualified) *StreamIDFullyQualifiedProto {
	return &StreamIDFullyQualifiedProto{
		PlatformId: id.PlatformID,
		AccountId:  id.AccountID,
		StreamId:   id.StreamID,
	}
}

func streamIDFromProto(p *StreamIDFullyQualifiedProto) backend.StreamIDFullyQualified {
	if p == nil {
		return backend.StreamIDFullyQualified{}
	}
	return backend.StreamIDFullyQualified{
		PlatformID: p.GetPlatformId(),
		AccountID:  p.GetAccountId(),
		StreamID:   p.GetStreamId(),
	}
}

func streamInfoToProto(s *backend.Stream) *StreamInfoProto {
	return &StreamInfoProto{
		Id:          streamIDToProto(s.ID),
		IsActive:    s.IsActive,
		Title:       s.Title,
		Description: s.Description,
	}
}

func streamSourceToProto(s *backend.StreamSource) *StreamSourceProto {
	return &StreamSourceProto{
		Id:       s.ID,
		Url:      s.URL,
		IsActive: s.IsActive,
	}
}

func streamSinkToProto(s *backend.StreamSink) *StreamSinkProto {
	proto := &StreamSinkProto{
		Id:  s.ID,
		Url: s.URL,
	}
	if s.EncoderConfig != nil {
		proto.EncoderConfig = encoderConfigToProto(s.EncoderConfig)
	}
	return proto
}

func encoderConfigToProto(c *backend.EncoderConfig) *EncoderConfigProto {
	if c == nil {
		return nil
	}
	return &EncoderConfigProto{
		AudioBitrate: c.AudioBitrate,
		VideoBitrate: c.VideoBitrate,
		VideoWidth:   c.VideoWidth,
		VideoHeight:  c.VideoHeight,
	}
}

func encoderConfigFromProto(p *EncoderConfigProto) *backend.EncoderConfig {
	if p == nil {
		return nil
	}
	return &backend.EncoderConfig{
		AudioBitrate: p.GetAudioBitrate(),
		VideoBitrate: p.GetVideoBitrate(),
		VideoWidth:   p.GetVideoWidth(),
		VideoHeight:  p.GetVideoHeight(),
	}
}

func streamForwardQuirksFromProto(q *StreamForwardQuirksProto) *backend.StreamForwardQuirks {
	if q == nil {
		return nil
	}
	return &backend.StreamForwardQuirks{
		RestartOnError:                 q.GetRestartOnError(),
		PlatformRecognitionWaitSeconds: q.GetPlatformRecognitionWaitSeconds(),
	}
}

func streamSinkFromProtoRequest(req *AddStreamSinkRequest) backend.StreamSink {
	sink := backend.StreamSink{
		ID:   req.GetSinkId(),
		Type: req.GetSinkType().String(),
		URL:  req.GetUrl(),
	}
	if ec := req.GetEncoderConfig(); ec != nil {
		sink.EncoderConfig = encoderConfigFromProto(ec)
	}
	return sink
}

func streamPlayerFromProto(p *StreamPlayerProto) backend.StreamPlayer {
	if p == nil {
		return backend.StreamPlayer{}
	}
	return backend.StreamPlayer{
		ID:       p.GetId(),
		Title:    p.GetTitle(),
		Link:     p.GetLink(),
		Position: p.GetPosition(),
		Length:   p.GetLength(),
		IsPaused: p.GetIsPaused(),
	}
}

func timerToProto(t *backend.Timer) *TimerProto {
	return &TimerProto{
		Id:              t.ID,
		IntervalSeconds: t.IntervalSeconds,
		Action:          actionToProto(&t.Action),
	}
}

func actionToProto(a *backend.Action) *ActionProto {
	return &ActionProto{
		Type:   a.Type,
		Params: a.Params,
	}
}

func timerFromProto(p *TimerProto) backend.Timer {
	if p == nil {
		return backend.Timer{}
	}
	t := backend.Timer{
		ID:              p.GetId(),
		IntervalSeconds: p.GetIntervalSeconds(),
	}
	if a := p.GetAction(); a != nil {
		t.Action = actionFromProto(a)
	}
	return t
}

func actionFromProto(p *ActionProto) backend.Action {
	if p == nil {
		return backend.Action{}
	}
	return backend.Action{
		Type:   p.GetType(),
		Params: p.GetParams(),
	}
}

func triggerRuleToProto(r *backend.TriggerRule) *TriggerRuleProto {
	return &TriggerRuleProto{
		Id:         r.ID,
		EventQuery: eventQueryToProto(&r.EventQuery),
		Action:     actionToProto(&r.Action),
		Enabled:    r.Enabled,
	}
}

func eventQueryToProto(q *backend.EventQuery) *EventQueryProto {
	return &EventQueryProto{
		Filter: q.Filter,
	}
}

func triggerRuleFromProto(p *TriggerRuleProto) backend.TriggerRule {
	if p == nil {
		return backend.TriggerRule{}
	}
	r := backend.TriggerRule{
		ID:      p.GetId(),
		Enabled: p.GetEnabled(),
	}
	if a := p.GetAction(); a != nil {
		r.Action = actionFromProto(a)
	}
	if eq := p.GetEventQuery(); eq != nil {
		r.EventQuery = backend.EventQuery{
			EventType: eq.GetEventType().String(),
			Filter:    eq.GetFilter(),
		}
	}
	return r
}

func chatEventFromProto(p *ChatEventProto) backend.ChatEvent {
	if p == nil {
		return backend.ChatEvent{}
	}
	ev := backend.ChatEvent{
		ID:                p.GetId(),
		CreatedAtUnixNano: p.GetCreatedAtUnixNano(),
		EventType:         p.GetEventType().String(),
		Platform:          p.GetPlatform().String(),
	}
	if u := p.GetUser(); u != nil {
		ev.User = chatUserFromProto(u)
	}
	if tu := p.GetTargetUser(); tu != nil {
		user := chatUserFromProto(tu)
		ev.TargetUser = &user
	}
	if m := p.GetMessage(); m != nil {
		mc := chatMessageContentFromProto(m)
		ev.MessageContent = &mc
	}
	if mo := p.GetMoney(); mo != nil {
		money := moneyFromProto(mo)
		ev.Money = &money
	}
	return ev
}

func chatUserFromProto(p *ChatUserProto) backend.ChatUser {
	if p == nil {
		return backend.ChatUser{}
	}
	return backend.ChatUser{
		ID:           p.GetId(),
		Slug:         p.GetSlug(),
		Name:         p.GetName(),
		NameReadable: p.GetNameReadable(),
	}
}

func chatMessageContentFromProto(p *ChatMessageContentProto) backend.ChatMessageContent {
	if p == nil {
		return backend.ChatMessageContent{}
	}
	return backend.ChatMessageContent{
		Content:    p.GetContent(),
		FormatType: p.GetFormatType().String(),
		InReplyTo:  p.GetInReplyTo(),
	}
}

func moneyFromProto(p *MoneyProto) backend.Money {
	if p == nil {
		return backend.Money{}
	}
	return backend.Money{
		Currency: p.GetCurrency().String(),
		Amount:   p.GetAmount(),
	}
}

func currentOutputToProto(o *backend.CurrentOutput) *CurrentOutputProto {
	if o == nil {
		return nil
	}
	return &CurrentOutputProto{
		OutputId: strconv.FormatUint(o.ID, 10),
	}
}

func senderPropsFromProto(props map[string]string) backend.SenderProps {
	// The proto sends properties as a map; parse known keys.
	var sp backend.SenderProps
	if v, ok := props["max_bitrate"]; ok {
		if br, err := strconv.ParseUint(v, 10, 64); err == nil {
			sp.MaxBitRate = br
		}
	}
	if v, ok := props["video_bitrate"]; ok {
		if br, err := strconv.ParseUint(v, 10, 64); err == nil {
			sp.Config.VideoBitRate = br
		}
	}
	if v, ok := props["audio_bitrate"]; ok {
		if br, err := strconv.ParseUint(v, 10, 64); err == nil {
			sp.Config.AudioBitRate = br
		}
	}
	if v, ok := props["video_width"]; ok {
		if w, err := strconv.ParseUint(v, 10, 32); err == nil {
			sp.Config.VideoWidth = uint32(w)
		}
	}
	if v, ok := props["video_height"]; ok {
		if h, err := strconv.ParseUint(v, 10, 32); err == nil {
			sp.Config.VideoHeight = uint32(h)
		}
	}
	return sp
}

func srtStatsToProto(s *backend.SRTStats) *SRTStatsProto {
	if s == nil {
		return nil
	}
	return &SRTStatsProto{
		PktSent:       s.PktSent,
		PktReceived:   s.PktRecv,
		PktSendLoss:   s.PktSendLoss,
		PktRecvLoss:   s.PktRecvLoss,
		PktRetrans:    s.PktRetrans,
		PktSendDrop:   s.PktSendDrop,
		PktRecvDrop:   s.PktRecvDrop,
		BytesSent:     s.BytesSent,
		BytesReceived: s.BytesRecv,
		BytesSendDrop: s.BytesSendDrop,
		BytesRecvDrop: s.BytesRecvDrop,
		RttMs:         s.RTTMS,
		BandwidthMbps: s.BandwidthMbps,
		SendRateMbps:  s.SendRateMbps,
		RecvRateMbps:  s.RecvRateMbps,
		PktFlightSize: s.PktFlightSize,
	}
}

func autoBitRateVideoConfigToProto(c *backend.AutoBitRateVideoConfig) *AutoBitRateVideoConfigProto {
	if c == nil {
		return nil
	}
	return &AutoBitRateVideoConfigProto{
		MinBitrate: uint64(c.MinHeight),
		MaxBitrate: uint64(c.MaxHeight),
	}
}

func autoBitRateVideoConfigFromProto(p *AutoBitRateVideoConfigProto) backend.AutoBitRateVideoConfig {
	if p == nil {
		return backend.AutoBitRateVideoConfig{}
	}
	return backend.AutoBitRateVideoConfig{
		MinHeight: uint32(p.GetMinBitrate()),
		MaxHeight: uint32(p.GetMaxBitrate()),
	}
}

func inputInfoToProto(i *backend.InputInfo) *InputInfoProto {
	return &InputInfoProto{
		Id:           strconv.FormatUint(i.ID, 10),
		Priority:     uint32(i.Priority),
		Url:          i.URL,
		IsActive:     i.IsActive,
		IsSuppressed: i.Suppressed,
	}
}

func diagnosticsFromProto(p *DiagnosticsProto) *backend.Diagnostics {
	if p == nil {
		return nil
	}
	d := &backend.Diagnostics{
		LatencyPreSending: p.LatencyPreSending,
		LatencySending:    p.LatencySending,
		FPSInput:          p.FpsInput,
		FPSOutput:         p.FpsOutput,
		BitrateVideo:      p.BitrateVideo,
		PlayerLagMin:      p.PlayerLagMin,
		PlayerLagMax:      p.PlayerLagMax,
		PingRTT:           p.PingRtt,
		WiFiSSID:          p.WifiSsid,
		WiFiBSSID:         p.WifiBssid,
		WiFiRSSI:          p.WifiRssi,
		Channels:          p.GetChannels(),
		ViewersYoutube:    p.ViewersYoutube,
		ViewersTwitch:     p.ViewersTwitch,
		ViewersKick:       p.ViewersKick,
		Signal:            p.Signal,
		StreamTime:        p.StreamTime,
		CPUUtilization:    p.CpuUtilization,
		MemoryUtilization: p.MemoryUtilization,
	}
	for _, t := range p.GetTemperatures() {
		d.Temperatures = append(d.Temperatures, backend.Temperature{
			Type: t.GetType(),
			Temp: t.GetTemp(),
		})
	}
	return d
}
