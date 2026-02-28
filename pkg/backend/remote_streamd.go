package backend

import (
	"context"
	"fmt"
	"strconv"
	"time"

	player_grpc "github.com/xaionaro-go/player/pkg/player/protobuf/go/player_grpc"
	sdgrpc "github.com/xaionaro-go/streamctl/pkg/streamd/grpc/go/streamd_grpc"
	"google.golang.org/grpc"
)

var _ StreamDBackend = (*RemoteStreamD)(nil)

// RemoteStreamD implements StreamDBackend by connecting to a native streamd gRPC server.
type RemoteStreamD struct {
	conn   *grpc.ClientConn
	client sdgrpc.StreamDClient
}

// NewRemoteStreamD dials the given address and returns a remote StreamD client.
// It probes the server to determine whether TLS is required, then connects accordingly.
func NewRemoteStreamD(addr string) (*RemoteStreamD, error) {
	creds := dialCredentials(addr)
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("dial streamd at %s: %w", addr, err)
	}
	return &RemoteStreamD{
		conn:   conn,
		client: sdgrpc.NewStreamDClient(conn),
	}, nil
}

// Close closes the gRPC connection.
func (r *RemoteStreamD) Close() error {
	return r.conn.Close()
}

func streamIDToSDProto(id StreamIDFullyQualified) *sdgrpc.StreamIDFullyQualified {
	return &sdgrpc.StreamIDFullyQualified{
		PlatformID: id.PlatformID,
		AccountID:  id.AccountID,
		StreamID:   id.StreamID,
	}
}

func streamIDFromSDProto(p *sdgrpc.StreamIDFullyQualified) StreamIDFullyQualified {
	if p == nil {
		return StreamIDFullyQualified{}
	}
	return StreamIDFullyQualified{
		PlatformID: p.GetPlatformID(),
		AccountID:  p.GetAccountID(),
		StreamID:   p.GetStreamID(),
	}
}

func (r *RemoteStreamD) Ping(ctx context.Context, payload string) (string, error) {
	resp, err := r.client.Ping(ctx, &sdgrpc.PingRequest{
		PayloadToReturn: payload,
	})
	if err != nil {
		return "", err
	}
	return resp.GetPayload(), nil
}

func (r *RemoteStreamD) SetLoggingLevel(ctx context.Context, level int) error {
	_, err := r.client.SetLoggingLevel(ctx, &sdgrpc.SetLoggingLevelRequest{
		LoggingLevel: sdgrpc.LoggingLevel(level),
	})
	return err
}

func (r *RemoteStreamD) GetLoggingLevel(ctx context.Context) (int, error) {
	resp, err := r.client.GetLoggingLevel(ctx, &sdgrpc.GetLoggingLevelRequest{})
	if err != nil {
		return 0, err
	}
	return int(resp.GetLoggingLevel()), nil
}

func (r *RemoteStreamD) GetConfig(ctx context.Context) (string, error) {
	resp, err := r.client.GetConfig(ctx, &sdgrpc.GetConfigRequest{})
	if err != nil {
		return "", err
	}
	return resp.GetConfig(), nil
}

func (r *RemoteStreamD) SetConfig(ctx context.Context, configYAML string) error {
	_, err := r.client.SetConfig(ctx, &sdgrpc.SetConfigRequest{
		Config: configYAML,
	})
	return err
}

func (r *RemoteStreamD) SaveConfig(ctx context.Context) error {
	_, err := r.client.SaveConfig(ctx, &sdgrpc.SaveConfigRequest{})
	return err
}

func (r *RemoteStreamD) SetStreamActive(ctx context.Context, streamID StreamIDFullyQualified, active bool) error {
	_, err := r.client.SetStreamActive(ctx, &sdgrpc.SetStreamActiveRequest{
		Id:       streamIDToSDProto(streamID),
		IsActive: active,
	})
	return err
}

func (r *RemoteStreamD) GetStreamStatus(ctx context.Context, streamID StreamIDFullyQualified, noCache bool) (*StreamStatus, error) {
	resp, err := r.client.GetStreamStatus(ctx, &sdgrpc.GetStreamStatusRequest{
		Id:      streamIDToSDProto(streamID),
		NoCache: noCache,
	})
	if err != nil {
		return nil, err
	}
	result := &StreamStatus{
		IsActive:   resp.GetIsActive(),
		CustomData: resp.GetCustomData(),
	}
	if startedAt := resp.GetStartedAt(); startedAt > 0 {
		t := time.Unix(startedAt, 0)
		result.StartedAt = &t
	}
	vc := resp.GetViewersCount()
	if vc > 0 {
		result.ViewersCount = &vc
	}
	return result, nil
}

func (r *RemoteStreamD) ListStreamSources(ctx context.Context) ([]StreamSource, error) {
	resp, err := r.client.ListStreamSources(ctx, &sdgrpc.ListStreamSourcesRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamSource
	for _, s := range resp.GetStreamSources() {
		result = append(result, StreamSource{
			ID: s.GetStreamSourceID(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) AddStreamSource(ctx context.Context, url string) error {
	_, err := r.client.AddStreamSource(ctx, &sdgrpc.AddStreamSourceRequest{
		StreamSourceID: url,
	})
	return err
}

func (r *RemoteStreamD) RemoveStreamSource(ctx context.Context, id string) error {
	_, err := r.client.RemoveStreamSource(ctx, &sdgrpc.RemoveStreamSourceRequest{
		StreamSourceID: id,
	})
	return err
}

func (r *RemoteStreamD) ListStreamSinks(ctx context.Context) ([]StreamSink, error) {
	resp, err := r.client.ListStreamSinks(ctx, &sdgrpc.ListStreamSinksRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamSink
	for _, s := range resp.GetStreamSinks() {
		sinkIDProto := s.GetStreamSinkID()
		sinkID := ""
		sinkType := ""
		if sinkIDProto != nil {
			sinkID = sinkIDProto.GetStreamSinkID()
			sinkType = sinkIDProto.GetType().String()
		}
		url := ""
		if cfg := s.GetConfig(); cfg != nil {
			url = cfg.GetUrl()
		}
		result = append(result, StreamSink{
			ID:   sinkID,
			Type: sinkType,
			URL:  url,
		})
	}
	return result, nil
}

func (r *RemoteStreamD) AddStreamSink(ctx context.Context, sink StreamSink) error {
	_, err := r.client.AddStreamSink(ctx, &sdgrpc.AddStreamSinkRequest{
		Config: &sdgrpc.StreamSink{
			StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
				StreamSinkID: sink.ID,
			},
			Config: &sdgrpc.StreamSinkConfig{
				Url: sink.URL,
			},
		},
	})
	return err
}

func (r *RemoteStreamD) RemoveStreamSink(ctx context.Context, id string) error {
	_, err := r.client.RemoveStreamSink(ctx, &sdgrpc.RemoveStreamSinkRequest{
		StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
			StreamSinkID: id,
		},
	})
	return err
}

func (r *RemoteStreamD) ListStreamForwards(ctx context.Context) ([]StreamForward, error) {
	resp, err := r.client.ListStreamForwards(ctx, &sdgrpc.ListStreamForwardsRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamForward
	for _, f := range resp.GetStreamForwards() {
		cfg := f.GetConfig()
		if cfg == nil {
			continue
		}
		sinkID := ""
		sinkType := ""
		if s := cfg.GetStreamSinkID(); s != nil {
			sinkID = s.GetStreamSinkID()
			sinkType = s.GetType().String()
		}
		result = append(result, StreamForward{
			SourceID: cfg.GetStreamSourceID(),
			SinkID:   sinkID,
			SinkType: sinkType,
			Enabled:  cfg.GetEnabled(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) AddStreamForward(ctx context.Context, fwd StreamForward) error {
	_, err := r.client.AddStreamForward(ctx, &sdgrpc.AddStreamForwardRequest{
		Config: &sdgrpc.StreamForward{
			StreamSourceID: fwd.SourceID,
			StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
				StreamSinkID: fwd.SinkID,
			},
			Enabled: fwd.Enabled,
		},
	})
	return err
}

func (r *RemoteStreamD) RemoveStreamForward(ctx context.Context, sourceID, sinkID string) error {
	_, err := r.client.RemoveStreamForward(ctx, &sdgrpc.RemoveStreamForwardRequest{
		Config: &sdgrpc.StreamForward{
			StreamSourceID: sourceID,
			StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
				StreamSinkID: sinkID,
			},
		},
	})
	return err
}

func (r *RemoteStreamD) ListStreamServers(ctx context.Context) ([]StreamServer, error) {
	resp, err := r.client.ListStreamServers(ctx, &sdgrpc.ListStreamServersRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamServer
	for _, s := range resp.GetStreamServers() {
		cfg := s.GetConfig()
		if cfg == nil {
			continue
		}
		result = append(result, StreamServer{
			Type:       cfg.GetServerType().String(),
			ListenAddr: cfg.GetListenAddr(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) ListStreamPlayers(ctx context.Context) ([]StreamPlayer, error) {
	resp, err := r.client.ListStreamPlayers(ctx, &sdgrpc.ListStreamPlayersRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamPlayer
	for _, p := range resp.GetPlayers() {
		result = append(result, StreamPlayer{
			ID: p.GetStreamSourceID(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) PlayerOpen(ctx context.Context, playerID string, url string) error {
	_, err := r.client.StreamPlayerOpen(ctx, &sdgrpc.StreamPlayerOpenRequest{
		StreamSourceID: playerID,
		Request:        &player_grpc.OpenRequest{Link: url},
	})
	return err
}

func (r *RemoteStreamD) PlayerClose(ctx context.Context, playerID string) error {
	_, err := r.client.StreamPlayerClose(ctx, &sdgrpc.StreamPlayerCloseRequest{
		StreamSourceID: playerID,
	})
	return err
}

func (r *RemoteStreamD) PlayerSetPause(ctx context.Context, playerID string, paused bool) error {
	_, err := r.client.StreamPlayerSetPause(ctx, &sdgrpc.StreamPlayerSetPauseRequest{
		StreamSourceID: playerID,
		Request:        &player_grpc.SetPauseRequest{IsPaused: paused},
	})
	return err
}

func (r *RemoteStreamD) PlayerGetLag(ctx context.Context, playerID string) (float64, error) {
	resp, err := r.client.StreamPlayerGetLag(ctx, &sdgrpc.StreamPlayerGetLagRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return 0, err
	}
	return float64(resp.GetLagU()) / 1e6, nil
}

// convertStreamDChatMessage converts a streamd gRPC ChatMessage to the backend ChatMessage type.
func convertStreamDChatMessage(msg *sdgrpc.ChatMessage) ChatMessage {
	cm := ChatMessage{
		Platform: msg.GetPlatID(),
	}
	if content := msg.GetContent(); content != nil {
		cm.EventType = content.GetEventType().String()
		if nanos := content.GetCreatedAtUNIXNano(); nanos > 0 {
			cm.Timestamp = int64(nanos / 1_000_000_000)
		}
		if user := content.GetUser(); user != nil {
			cm.UserName = user.GetName()
			cm.User = ChatUser{
				ID:   user.GetId(),
				Name: user.GetName(),
			}
		}
		if mc := content.GetMessage(); mc != nil {
			cm.Message = mc.GetContent()
			cm.MessageContent = ChatMessageContent{
				Content: mc.GetContent(),
			}
		}
	}
	return cm
}

func (r *RemoteStreamD) SubscribeToChatMessages(ctx context.Context, since int64, limit int32) (<-chan ChatMessage, error) {
	stream, err := r.client.SubscribeToChatMessages(ctx, &sdgrpc.SubscribeToChatMessagesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan ChatMessage)
	go func() {
		defer close(ch)
		for {
			msg, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- convertStreamDChatMessage(msg):
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SendChatMessage(ctx context.Context, platform, accountID, message string) error {
	_, err := r.client.SendChatMessage(ctx, &sdgrpc.SendChatMessageRequest{
		PlatID:  platform,
		Message: message,
	})
	return err
}

func (r *RemoteStreamD) ListProfiles(ctx context.Context) ([]Profile, error) {
	resp, err := r.client.ListProfiles(ctx, &sdgrpc.ListProfilesRequest{})
	if err != nil {
		return nil, err
	}
	var result []Profile
	for _, p := range resp.GetProfiles() {
		result = append(result, Profile{
			Name: p.GetName(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) ApplyProfile(ctx context.Context, streamID StreamIDFullyQualified, profileName string) error {
	_, err := r.client.ApplyProfile(ctx, &sdgrpc.ApplyProfileRequest{
		Id:      streamIDToSDProto(streamID),
		Profile: profileName,
	})
	return err
}

func (r *RemoteStreamD) GetAccounts(ctx context.Context, platformIDs []string) ([]Account, error) {
	resp, err := r.client.GetAccounts(ctx, &sdgrpc.GetAccountsRequest{})
	if err != nil {
		return nil, err
	}
	var result []Account
	for _, a := range resp.GetAccountIDs() {
		result = append(result, Account{
			PlatformID: a.GetPlatformID(),
			AccountID:  a.GetAccountID(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) GetVariable(ctx context.Context, key string) ([]byte, error) {
	resp, err := r.client.GetVariable(ctx, &sdgrpc.GetVariableRequest{
		Key: key,
	})
	if err != nil {
		return nil, err
	}
	return resp.GetValue(), nil
}

func (r *RemoteStreamD) SetVariable(ctx context.Context, key string, value []byte) error {
	_, err := r.client.SetVariable(ctx, &sdgrpc.SetVariableRequest{
		Key:   key,
		Value: value,
	})
	return err
}

func (r *RemoteStreamD) SubscribeToVariable(ctx context.Context, key string) (<-chan []byte, error) {
	stream, err := r.client.SubscribeToVariable(ctx, &sdgrpc.SubscribeToVariableRequest{
		Key: key,
	})
	if err != nil {
		return nil, err
	}
	ch := make(chan []byte)
	go func() {
		defer close(ch)
		for {
			msg, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- msg.GetValue():
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) ResetCache(ctx context.Context) error {
	_, err := r.client.ResetCache(ctx, &sdgrpc.ResetCacheRequest{})
	return err
}

func (r *RemoteStreamD) InitCache(ctx context.Context) error {
	_, err := r.client.InitCache(ctx, &sdgrpc.InitCacheRequest{})
	return err
}

func (r *RemoteStreamD) GetStreams(ctx context.Context) ([]Stream, error) {
	resp, err := r.client.GetStreams(ctx, &sdgrpc.GetStreamsRequest{})
	if err != nil {
		return nil, err
	}
	var result []Stream
	for _, s := range resp.GetStreams() {
		result = append(result, Stream{
			ID:    StreamIDFullyQualified{StreamID: s.GetID()},
			Title: s.GetName(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) CreateStream(ctx context.Context, platformID string, title string, description string, profile string) error {
	_, err := r.client.CreateStream(ctx, &sdgrpc.CreateStreamRequest{
		AccountID: &sdgrpc.AccountIDFullyQualified{
			PlatformID: platformID,
		},
		Title: title,
	})
	return err
}

func (r *RemoteStreamD) DeleteStream(ctx context.Context, streamID StreamIDFullyQualified) error {
	_, err := r.client.DeleteStream(ctx, &sdgrpc.DeleteStreamRequest{
		StreamID: streamIDToSDProto(streamID),
	})
	return err
}

func (r *RemoteStreamD) GetActiveStreamIDs(ctx context.Context) ([]StreamIDFullyQualified, error) {
	resp, err := r.client.GetActiveStreamIDs(ctx, &sdgrpc.GetActiveStreamIDsRequest{})
	if err != nil {
		return nil, err
	}
	var result []StreamIDFullyQualified
	for _, id := range resp.GetStreamSourceIDs() {
		result = append(result, streamIDFromSDProto(id))
	}
	return result, nil
}

func (r *RemoteStreamD) StartStream(ctx context.Context, platID string, profileName string) error {
	return fmt.Errorf("StartStream is not supported for remote streamd")
}

func (r *RemoteStreamD) EndStream(ctx context.Context, platID string) error {
	return fmt.Errorf("EndStream is not supported for remote streamd")
}

func (r *RemoteStreamD) IsBackendEnabled(ctx context.Context, platformID string) (bool, error) {
	resp, err := r.client.IsBackendEnabled(ctx, &sdgrpc.IsBackendEnabledRequest{
		PlatID: platformID,
	})
	if err != nil {
		return false, err
	}
	return resp.GetIsInitialized(), nil
}

func (r *RemoteStreamD) GetBackendInfo(ctx context.Context, platformID string) (*BackendInfo, error) {
	resp, err := r.client.GetBackendInfo(ctx, &sdgrpc.GetBackendInfoRequest{
		PlatID: platformID,
	})
	if err != nil {
		return nil, err
	}
	var caps []string
	for _, c := range resp.GetCapabilities() {
		caps = append(caps, c.String())
	}
	return &BackendInfo{
		PlatformID:   platformID,
		Capabilities: caps,
	}, nil
}

func (r *RemoteStreamD) GetPlatforms(ctx context.Context) ([]string, error) {
	resp, err := r.client.GetPlatforms(ctx, &sdgrpc.GetPlatformsRequest{})
	if err != nil {
		return nil, err
	}
	return resp.GetPlatformIDs(), nil
}

func (r *RemoteStreamD) SetTitle(ctx context.Context, platID string, title string) error {
	_, err := r.client.SetTitle(ctx, &sdgrpc.SetTitleRequest{
		Id:    &sdgrpc.StreamIDFullyQualified{PlatformID: platID},
		Title: title,
	})
	return err
}

func (r *RemoteStreamD) SetDescription(ctx context.Context, platID string, description string) error {
	_, err := r.client.SetDescription(ctx, &sdgrpc.SetDescriptionRequest{
		Id:          &sdgrpc.StreamIDFullyQualified{PlatformID: platID},
		Description: description,
	})
	return err
}

func (r *RemoteStreamD) GetVariableHash(ctx context.Context, key string, hashType string) (string, error) {
	ht, err := strconv.Atoi(hashType)
	if err != nil {
		ht = 0
	}
	resp, err := r.client.GetVariableHash(ctx, &sdgrpc.GetVariableHashRequest{
		Key:      key,
		HashType: sdgrpc.HashType(ht),
	})
	if err != nil {
		return "", err
	}
	return string(resp.GetHash()), nil
}

func (r *RemoteStreamD) SubscribeToOAuthRequests(ctx context.Context) (<-chan OAuthRequest, error) {
	stream, err := r.client.SubscribeToOAuthRequests(ctx, &sdgrpc.SubscribeToOAuthRequestsRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan OAuthRequest)
	go func() {
		defer close(ch)
		for {
			msg, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- OAuthRequest{
				RequestID:  msg.GetPlatID(),
				AuthURL:    msg.GetAuthURL(),
				PlatformID: msg.GetPlatID(),
			}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubmitOAuthCode(ctx context.Context, requestID string, code string) error {
	_, err := r.client.SubmitOAuthCode(ctx, &sdgrpc.SubmitOAuthCodeRequest{
		PlatID: requestID,
		Code:   code,
	})
	return err
}

func (r *RemoteStreamD) StartStreamServer(ctx context.Context, config StreamServer) error {
	_, err := r.client.StartStreamServer(ctx, &sdgrpc.StartStreamServerRequest{
		Config: &sdgrpc.StreamServer{
			ListenAddr: config.ListenAddr,
		},
	})
	return err
}

func (r *RemoteStreamD) StopStreamServer(ctx context.Context, serverID string) error {
	_, err := r.client.StopStreamServer(ctx, &sdgrpc.StopStreamServerRequest{
		ListenAddr: serverID,
	})
	return err
}

func (r *RemoteStreamD) UpdateStreamSink(ctx context.Context, sink StreamSink) error {
	_, err := r.client.UpdateStreamSink(ctx, &sdgrpc.UpdateStreamSinkRequest{
		Config: &sdgrpc.StreamSink{
			StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
				StreamSinkID: sink.ID,
			},
			Config: &sdgrpc.StreamSinkConfig{
				Url: sink.URL,
			},
		},
	})
	return err
}

func (r *RemoteStreamD) GetStreamSinkConfig(ctx context.Context, sinkID string) (*StreamSinkConfig, error) {
	resp, err := r.client.GetStreamSinkConfig(ctx, &sdgrpc.GetStreamSinkConfigRequest{
		StreamSourceID: &sdgrpc.StreamIDFullyQualified{
			StreamID: sinkID,
		},
	})
	if err != nil {
		return nil, err
	}
	cfg := resp.GetConfig()
	url := ""
	if cfg != nil {
		url = cfg.GetUrl()
	}
	return &StreamSinkConfig{
		URL: url,
	}, nil
}

func (r *RemoteStreamD) UpdateStreamForward(ctx context.Context, fwd StreamForward) error {
	_, err := r.client.UpdateStreamForward(ctx, &sdgrpc.UpdateStreamForwardRequest{
		Config: &sdgrpc.StreamForward{
			StreamSourceID: fwd.SourceID,
			StreamSinkID: &sdgrpc.StreamSinkIDFullyQualified{
				StreamSinkID: fwd.SinkID,
			},
			Enabled: fwd.Enabled,
		},
	})
	return err
}

func (r *RemoteStreamD) AddStreamPlayer(ctx context.Context, player StreamPlayer) error {
	_, err := r.client.AddStreamPlayer(ctx, &sdgrpc.AddStreamPlayerRequest{
		Config: &sdgrpc.StreamPlayerConfig{
			StreamSourceID: player.ID,
		},
	})
	return err
}

func (r *RemoteStreamD) RemoveStreamPlayer(ctx context.Context, playerID string) error {
	_, err := r.client.RemoveStreamPlayer(ctx, &sdgrpc.RemoveStreamPlayerRequest{
		StreamSourceID: playerID,
	})
	return err
}

func (r *RemoteStreamD) UpdateStreamPlayer(ctx context.Context, player StreamPlayer) error {
	_, err := r.client.UpdateStreamPlayer(ctx, &sdgrpc.UpdateStreamPlayerRequest{})
	return err
}

func (r *RemoteStreamD) GetStreamPlayer(ctx context.Context, playerID string) (*StreamPlayer, error) {
	resp, err := r.client.GetStreamPlayer(ctx, &sdgrpc.GetStreamPlayerRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return nil, err
	}
	cfg := resp.GetConfig()
	id := playerID
	if cfg != nil {
		id = cfg.GetStreamSourceID()
	}
	return &StreamPlayer{ID: id}, nil
}

func (r *RemoteStreamD) PlayerProcessTitle(ctx context.Context, playerID string, title string) (string, error) {
	resp, err := r.client.StreamPlayerProcessTitle(ctx, &sdgrpc.StreamPlayerProcessTitleRequest{
		StreamSourceID: playerID,
		Request:        &player_grpc.ProcessTitleRequest{},
	})
	if err != nil {
		return "", err
	}
	if reply := resp.GetReply(); reply != nil {
		return reply.GetTitle(), nil
	}
	return "", nil
}

func (r *RemoteStreamD) PlayerGetLink(ctx context.Context, playerID string) (string, error) {
	resp, err := r.client.StreamPlayerGetLink(ctx, &sdgrpc.StreamPlayerGetLinkRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return "", err
	}
	if reply := resp.GetReply(); reply != nil {
		return reply.GetLink(), nil
	}
	return "", nil
}

func (r *RemoteStreamD) PlayerIsEnded(ctx context.Context, playerID string) (bool, error) {
	resp, err := r.client.StreamPlayerIsEnded(ctx, &sdgrpc.StreamPlayerIsEndedRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return false, err
	}
	if reply := resp.GetReply(); reply != nil {
		return reply.GetIsEnded(), nil
	}
	return false, nil
}

func (r *RemoteStreamD) PlayerGetPosition(ctx context.Context, playerID string) (float64, error) {
	resp, err := r.client.StreamPlayerGetPosition(ctx, &sdgrpc.StreamPlayerGetPositionRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return 0, err
	}
	if reply := resp.GetReply(); reply != nil {
		return reply.GetPositionSecs(), nil
	}
	return 0, nil
}

func (r *RemoteStreamD) PlayerGetLength(ctx context.Context, playerID string) (float64, error) {
	resp, err := r.client.StreamPlayerGetLength(ctx, &sdgrpc.StreamPlayerGetLengthRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return 0, err
	}
	if reply := resp.GetReply(); reply != nil {
		return reply.GetLengthSecs(), nil
	}
	return 0, nil
}

func (r *RemoteStreamD) PlayerSetSpeed(ctx context.Context, playerID string, speed float64) error {
	_, err := r.client.StreamPlayerSetSpeed(ctx, &sdgrpc.StreamPlayerSetSpeedRequest{
		StreamSourceID: playerID,
		Request:        &player_grpc.SetSpeedRequest{Speed: speed},
	})
	return err
}

func (r *RemoteStreamD) PlayerGetSpeed(ctx context.Context, playerID string) (float64, error) {
	return 0, fmt.Errorf("PlayerGetSpeed is not supported for remote streamd")
}

func (r *RemoteStreamD) PlayerStop(ctx context.Context, playerID string) error {
	_, err := r.client.StreamPlayerStop(ctx, &sdgrpc.StreamPlayerStopRequest{
		StreamSourceID: playerID,
	})
	return err
}

func (r *RemoteStreamD) RemoveChatMessage(ctx context.Context, platID string, messageID string) error {
	_, err := r.client.RemoveChatMessage(ctx, &sdgrpc.RemoveChatMessageRequest{
		PlatID:    platID,
		MessageID: messageID,
	})
	return err
}

func (r *RemoteStreamD) BanUser(ctx context.Context, platID string, userID string, reason string, durationSeconds int64) error {
	req := &sdgrpc.BanUserRequest{
		PlatID: platID,
		UserID: userID,
		Reason: reason,
	}
	if durationSeconds > 0 {
		deadline := time.Now().Add(time.Duration(durationSeconds) * time.Second).UnixNano()
		req.DeadlineUnixNano = &deadline
	}
	_, err := r.client.BanUser(ctx, req)
	return err
}

func (r *RemoteStreamD) InjectPlatformEvent(ctx context.Context, event ChatEvent) error {
	return fmt.Errorf("InjectPlatformEvent is not supported for remote streamd")
}

func (r *RemoteStreamD) Shoutout(ctx context.Context, platID string, targetUserName string) error {
	_, err := r.client.Shoutout(ctx, &sdgrpc.ShoutoutRequest{
		PlatID: platID,
		UserID: targetUserName,
	})
	return err
}

func (r *RemoteStreamD) RaidTo(ctx context.Context, platID string, targetChannel string) error {
	_, err := r.client.RaidTo(ctx, &sdgrpc.RaidToRequest{
		PlatID: platID,
		UserID: targetChannel,
	})
	return err
}

func (r *RemoteStreamD) GetPeerIDs(ctx context.Context) ([]string, error) {
	resp, err := r.client.GetPeerIDs(ctx, &sdgrpc.GetPeerIDsRequest{})
	if err != nil {
		return nil, err
	}
	return resp.GetPeerIDs(), nil
}

func (r *RemoteStreamD) AddTimer(ctx context.Context, timer Timer) error {
	intervalSecs, _ := strconv.ParseUint(timer.ID, 10, 32)
	_, err := r.client.AddTimer(ctx, &sdgrpc.AddTimerRequest{
		TriggerAtUnixNano: int64(intervalSecs),
	})
	return err
}

func (r *RemoteStreamD) RemoveTimer(ctx context.Context, timerID string) error {
	id, _ := strconv.ParseInt(timerID, 10, 64)
	_, err := r.client.RemoveTimer(ctx, &sdgrpc.RemoveTimerRequest{
		TimerID: id,
	})
	return err
}

func (r *RemoteStreamD) ListTimers(ctx context.Context) ([]Timer, error) {
	resp, err := r.client.ListTimers(ctx, &sdgrpc.ListTimersRequest{})
	if err != nil {
		return nil, err
	}
	var result []Timer
	for _, t := range resp.GetTimers() {
		result = append(result, Timer{
			ID: strconv.FormatInt(t.GetTimerID(), 10),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) ListTriggerRules(ctx context.Context) ([]TriggerRule, error) {
	resp, err := r.client.ListTriggerRules(ctx, &sdgrpc.ListTriggerRulesRequest{})
	if err != nil {
		return nil, err
	}
	var result []TriggerRule
	for _, rule := range resp.GetRules() {
		result = append(result, TriggerRule{
			ID: rule.GetDescription(),
		})
	}
	return result, nil
}

func (r *RemoteStreamD) AddTriggerRule(ctx context.Context, rule TriggerRule) error {
	_, err := r.client.AddTriggerRule(ctx, &sdgrpc.AddTriggerRuleRequest{})
	return err
}

func (r *RemoteStreamD) RemoveTriggerRule(ctx context.Context, ruleID string) error {
	_, err := r.client.RemoveTriggerRule(ctx, &sdgrpc.RemoveTriggerRuleRequest{})
	return err
}

func (r *RemoteStreamD) UpdateTriggerRule(ctx context.Context, rule TriggerRule) error {
	_, err := r.client.UpdateTriggerRule(ctx, &sdgrpc.UpdateTriggerRuleRequest{})
	return err
}

func (r *RemoteStreamD) SubmitEvent(ctx context.Context, event Event) error {
	_, err := r.client.SubmitEvent(ctx, &sdgrpc.SubmitEventRequest{})
	return err
}

func (r *RemoteStreamD) LLMGenerate(ctx context.Context, prompt string) (string, error) {
	resp, err := r.client.LLMGenerate(ctx, &sdgrpc.LLMGenerateRequest{
		Prompt: prompt,
	})
	if err != nil {
		return "", err
	}
	return resp.GetResponse(), nil
}

func (r *RemoteStreamD) Restart(ctx context.Context) error {
	_, err := r.client.Restart(ctx, &sdgrpc.RestartRequest{})
	return err
}

func (r *RemoteStreamD) ReinitStreamControllers(ctx context.Context) error {
	_, err := r.client.EXPERIMENTAL_ReinitStreamControllers(ctx, &sdgrpc.EXPERIMENTAL_ReinitStreamControllersRequest{})
	return err
}

func (r *RemoteStreamD) SubscribeToConfigChanges(ctx context.Context) (<-chan string, error) {
	stream, err := r.client.SubscribeToConfigChanges(ctx, &sdgrpc.SubscribeToConfigChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan string)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- "":
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamsChanges(ctx context.Context) (<-chan Stream, error) {
	stream, err := r.client.SubscribeToStreamsChanges(ctx, &sdgrpc.SubscribeToStreamsChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan Stream)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- Stream{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamServersChanges(ctx context.Context) (<-chan StreamServer, error) {
	stream, err := r.client.SubscribeToStreamServersChanges(ctx, &sdgrpc.SubscribeToStreamServersChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan StreamServer)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- StreamServer{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamSourcesChanges(ctx context.Context) (<-chan StreamSource, error) {
	stream, err := r.client.SubscribeToStreamSourcesChanges(ctx, &sdgrpc.SubscribeToStreamSourcesChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan StreamSource)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- StreamSource{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamSinksChanges(ctx context.Context) (<-chan StreamSink, error) {
	stream, err := r.client.SubscribeToStreamSinksChanges(ctx, &sdgrpc.SubscribeToStreamSinksChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan StreamSink)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- StreamSink{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamForwardsChanges(ctx context.Context) (<-chan StreamForward, error) {
	stream, err := r.client.SubscribeToStreamForwardsChanges(ctx, &sdgrpc.SubscribeToStreamForwardsChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan StreamForward)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- StreamForward{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) SubscribeToStreamPlayersChanges(ctx context.Context) (<-chan StreamPlayer, error) {
	stream, err := r.client.SubscribeToStreamPlayersChanges(ctx, &sdgrpc.SubscribeToStreamPlayersChangesRequest{})
	if err != nil {
		return nil, err
	}
	ch := make(chan StreamPlayer)
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case ch <- StreamPlayer{}:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (r *RemoteStreamD) WaitForStreamPublisher(ctx context.Context, sourceID string) error {
	stream, err := r.client.WaitForStreamPublisher(ctx, &sdgrpc.WaitForStreamPublisherRequest{
		StreamSourceID: &sourceID,
	})
	if err != nil {
		return err
	}
	_, err = stream.Recv()
	return err
}

func (r *RemoteStreamD) PlayerEndChan(ctx context.Context, playerID string) (<-chan struct{}, error) {
	stream, err := r.client.StreamPlayerEndChan(ctx, &sdgrpc.StreamPlayerEndChanRequest{
		StreamSourceID: playerID,
	})
	if err != nil {
		return nil, err
	}
	ch := make(chan struct{})
	go func() {
		defer close(ch)
		for {
			_, err := stream.Recv()
			if err != nil {
				return
			}
		}
	}()
	return ch, nil
}
