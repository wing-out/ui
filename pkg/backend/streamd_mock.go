package backend

import (
	"context"
	"sync"
)

// MockStreamD is a mock implementation of StreamDBackend for testing.
type MockStreamD struct {
	mu sync.Mutex

	// Function fields for injectable behavior
	PingFunc                    func(ctx context.Context, payload string) (string, error)
	SetLoggingLevelFunc         func(ctx context.Context, level int) error
	GetLoggingLevelFunc         func(ctx context.Context) (int, error)
	GetConfigFunc               func(ctx context.Context) (string, error)
	SetConfigFunc               func(ctx context.Context, configYAML string) error
	SaveConfigFunc              func(ctx context.Context) error
	SetStreamActiveFunc         func(ctx context.Context, streamID StreamIDFullyQualified, active bool) error
	GetStreamStatusFunc         func(ctx context.Context, streamID StreamIDFullyQualified, noCache bool) (*StreamStatus, error)
	ListStreamSourcesFunc       func(ctx context.Context) ([]StreamSource, error)
	AddStreamSourceFunc         func(ctx context.Context, url string) error
	RemoveStreamSourceFunc      func(ctx context.Context, id string) error
	ListStreamSinksFunc         func(ctx context.Context) ([]StreamSink, error)
	AddStreamSinkFunc           func(ctx context.Context, sink StreamSink) error
	RemoveStreamSinkFunc        func(ctx context.Context, id string) error
	ListStreamForwardsFunc      func(ctx context.Context) ([]StreamForward, error)
	AddStreamForwardFunc        func(ctx context.Context, fwd StreamForward) error
	RemoveStreamForwardFunc     func(ctx context.Context, sourceID, sinkID string) error
	ListStreamServersFunc       func(ctx context.Context) ([]StreamServer, error)
	ListStreamPlayersFunc       func(ctx context.Context) ([]StreamPlayer, error)
	PlayerOpenFunc              func(ctx context.Context, playerID string, url string) error
	PlayerCloseFunc             func(ctx context.Context, playerID string) error
	PlayerSetPauseFunc          func(ctx context.Context, playerID string, paused bool) error
	PlayerGetLagFunc            func(ctx context.Context, playerID string) (float64, error)
	SubscribeToChatMessagesFunc func(ctx context.Context, since int64, limit int32, streamID string) (<-chan ChatMessage, error)
	SendChatMessageFunc         func(ctx context.Context, platform, accountID, message string) error
	ListProfilesFunc            func(ctx context.Context) ([]Profile, error)
	ApplyProfileFunc            func(ctx context.Context, streamID StreamIDFullyQualified, profileName string) error
	GetAccountsFunc             func(ctx context.Context, platformIDs []string) ([]Account, error)
	GetVariableFunc             func(ctx context.Context, key string) ([]byte, error)
	SetVariableFunc             func(ctx context.Context, key string, value []byte) error
	SubscribeToVariableFunc     func(ctx context.Context, key string) (<-chan []byte, error)

	ResetCacheFunc                      func(ctx context.Context) error
	InitCacheFunc                       func(ctx context.Context) error
	GetStreamsFunc                       func(ctx context.Context) ([]Stream, error)
	CreateStreamFunc                    func(ctx context.Context, platformID string, title string, description string, profile string) error
	DeleteStreamFunc                    func(ctx context.Context, streamID StreamIDFullyQualified) error
	GetActiveStreamIDsFunc              func(ctx context.Context) ([]StreamIDFullyQualified, error)
	StartStreamFunc                     func(ctx context.Context, platID string, profileName string) error
	EndStreamFunc                       func(ctx context.Context, platID string) error
	IsBackendEnabledFunc                func(ctx context.Context, platformID string) (bool, error)
	GetBackendInfoFunc                  func(ctx context.Context, platformID string) (*BackendInfo, error)
	GetPlatformsFunc                    func(ctx context.Context) ([]string, error)
	SetTitleFunc                        func(ctx context.Context, platID string, title string) error
	SetDescriptionFunc                  func(ctx context.Context, platID string, description string) error
	GetVariableHashFunc                 func(ctx context.Context, key string, hashType string) (string, error)
	SubscribeToOAuthRequestsFunc        func(ctx context.Context) (<-chan OAuthRequest, error)
	SubmitOAuthCodeFunc                 func(ctx context.Context, requestID string, code string) error
	StartStreamServerFunc               func(ctx context.Context, config StreamServer) error
	StopStreamServerFunc                func(ctx context.Context, serverID string) error
	UpdateStreamSinkFunc                func(ctx context.Context, sink StreamSink) error
	GetStreamSinkConfigFunc             func(ctx context.Context, sinkID string) (*StreamSinkConfig, error)
	UpdateStreamForwardFunc             func(ctx context.Context, fwd StreamForward) error
	AddStreamPlayerFunc                 func(ctx context.Context, player StreamPlayer) error
	RemoveStreamPlayerFunc              func(ctx context.Context, playerID string) error
	UpdateStreamPlayerFunc              func(ctx context.Context, player StreamPlayer) error
	GetStreamPlayerFunc                 func(ctx context.Context, playerID string) (*StreamPlayer, error)
	PlayerProcessTitleFunc              func(ctx context.Context, playerID string, title string) (string, error)
	PlayerGetLinkFunc                   func(ctx context.Context, playerID string) (string, error)
	PlayerIsEndedFunc                   func(ctx context.Context, playerID string) (bool, error)
	PlayerGetPositionFunc               func(ctx context.Context, playerID string) (float64, error)
	PlayerGetLengthFunc                 func(ctx context.Context, playerID string) (float64, error)
	PlayerSetSpeedFunc                  func(ctx context.Context, playerID string, speed float64) error
	PlayerGetSpeedFunc                  func(ctx context.Context, playerID string) (float64, error)
	PlayerStopFunc                      func(ctx context.Context, playerID string) error
	RemoveChatMessageFunc               func(ctx context.Context, platID string, messageID string) error
	BanUserFunc                         func(ctx context.Context, platID string, userID string, reason string, durationSeconds int64) error
	InjectPlatformEventFunc             func(ctx context.Context, event ChatEvent) error
	ShoutoutFunc                        func(ctx context.Context, platID string, targetUserName string) error
	RaidToFunc                          func(ctx context.Context, platID string, targetChannel string) error
	GetPeerIDsFunc                      func(ctx context.Context) ([]string, error)
	AddTimerFunc                        func(ctx context.Context, timer Timer) error
	RemoveTimerFunc                     func(ctx context.Context, timerID string) error
	ListTimersFunc                      func(ctx context.Context) ([]Timer, error)
	ListTriggerRulesFunc                func(ctx context.Context) ([]TriggerRule, error)
	AddTriggerRuleFunc                  func(ctx context.Context, rule TriggerRule) error
	RemoveTriggerRuleFunc               func(ctx context.Context, ruleID string) error
	UpdateTriggerRuleFunc               func(ctx context.Context, rule TriggerRule) error
	SubmitEventFunc                     func(ctx context.Context, event Event) error
	LLMGenerateFunc                     func(ctx context.Context, prompt string) (string, error)
	RestartFunc                         func(ctx context.Context) error
	ReinitStreamControllersFunc         func(ctx context.Context) error
	SubscribeToConfigChangesFunc        func(ctx context.Context) (<-chan string, error)
	SubscribeToStreamsChangesFunc        func(ctx context.Context) (<-chan Stream, error)
	SubscribeToStreamServersChangesFunc func(ctx context.Context) (<-chan StreamServer, error)
	SubscribeToStreamSourcesChangesFunc func(ctx context.Context) (<-chan StreamSource, error)
	SubscribeToStreamSinksChangesFunc   func(ctx context.Context) (<-chan StreamSink, error)
	SubscribeToStreamForwardsChangesFunc func(ctx context.Context) (<-chan StreamForward, error)
	SubscribeToStreamPlayersChangesFunc func(ctx context.Context) (<-chan StreamPlayer, error)
	WaitForStreamPublisherFunc          func(ctx context.Context, sourceID string) error
	PlayerEndChanFunc                   func(ctx context.Context, playerID string) (<-chan struct{}, error)

	// Call tracking
	Calls map[string]int
}

// NewMockStreamD creates a new MockStreamD with default no-op implementations.
func NewMockStreamD() *MockStreamD {
	return &MockStreamD{
		Calls: make(map[string]int),
	}
}

func (m *MockStreamD) trackCall(name string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls[name]++
}

// CallCount returns the number of times a method was called.
func (m *MockStreamD) CallCount(name string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.Calls[name]
}

// ResetCallCounts resets all call counters to zero.
func (m *MockStreamD) ResetCallCounts() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = make(map[string]int)
}

func (m *MockStreamD) Ping(ctx context.Context, payload string) (string, error) {
	m.trackCall("Ping")
	if m.PingFunc != nil {
		return m.PingFunc(ctx, payload)
	}
	return payload, nil
}

func (m *MockStreamD) SetLoggingLevel(ctx context.Context, level int) error {
	m.trackCall("SetLoggingLevel")
	if m.SetLoggingLevelFunc != nil {
		return m.SetLoggingLevelFunc(ctx, level)
	}
	return nil
}

func (m *MockStreamD) GetLoggingLevel(ctx context.Context) (int, error) {
	m.trackCall("GetLoggingLevel")
	if m.GetLoggingLevelFunc != nil {
		return m.GetLoggingLevelFunc(ctx)
	}
	return 5, nil
}

func (m *MockStreamD) GetConfig(ctx context.Context) (string, error) {
	m.trackCall("GetConfig")
	if m.GetConfigFunc != nil {
		return m.GetConfigFunc(ctx)
	}
	return "{}", nil
}

func (m *MockStreamD) SetConfig(ctx context.Context, configYAML string) error {
	m.trackCall("SetConfig")
	if m.SetConfigFunc != nil {
		return m.SetConfigFunc(ctx, configYAML)
	}
	return nil
}

func (m *MockStreamD) SaveConfig(ctx context.Context) error {
	m.trackCall("SaveConfig")
	if m.SaveConfigFunc != nil {
		return m.SaveConfigFunc(ctx)
	}
	return nil
}

func (m *MockStreamD) SetStreamActive(ctx context.Context, streamID StreamIDFullyQualified, active bool) error {
	m.trackCall("SetStreamActive")
	if m.SetStreamActiveFunc != nil {
		return m.SetStreamActiveFunc(ctx, streamID, active)
	}
	return nil
}

func (m *MockStreamD) GetStreamStatus(ctx context.Context, streamID StreamIDFullyQualified, noCache bool) (*StreamStatus, error) {
	m.trackCall("GetStreamStatus")
	if m.GetStreamStatusFunc != nil {
		return m.GetStreamStatusFunc(ctx, streamID, noCache)
	}
	return &StreamStatus{}, nil
}

func (m *MockStreamD) ListStreamSources(ctx context.Context) ([]StreamSource, error) {
	m.trackCall("ListStreamSources")
	if m.ListStreamSourcesFunc != nil {
		return m.ListStreamSourcesFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) AddStreamSource(ctx context.Context, url string) error {
	m.trackCall("AddStreamSource")
	if m.AddStreamSourceFunc != nil {
		return m.AddStreamSourceFunc(ctx, url)
	}
	return nil
}

func (m *MockStreamD) RemoveStreamSource(ctx context.Context, id string) error {
	m.trackCall("RemoveStreamSource")
	if m.RemoveStreamSourceFunc != nil {
		return m.RemoveStreamSourceFunc(ctx, id)
	}
	return nil
}

func (m *MockStreamD) ListStreamSinks(ctx context.Context) ([]StreamSink, error) {
	m.trackCall("ListStreamSinks")
	if m.ListStreamSinksFunc != nil {
		return m.ListStreamSinksFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) AddStreamSink(ctx context.Context, sink StreamSink) error {
	m.trackCall("AddStreamSink")
	if m.AddStreamSinkFunc != nil {
		return m.AddStreamSinkFunc(ctx, sink)
	}
	return nil
}

func (m *MockStreamD) RemoveStreamSink(ctx context.Context, id string) error {
	m.trackCall("RemoveStreamSink")
	if m.RemoveStreamSinkFunc != nil {
		return m.RemoveStreamSinkFunc(ctx, id)
	}
	return nil
}

func (m *MockStreamD) ListStreamForwards(ctx context.Context) ([]StreamForward, error) {
	m.trackCall("ListStreamForwards")
	if m.ListStreamForwardsFunc != nil {
		return m.ListStreamForwardsFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) AddStreamForward(ctx context.Context, fwd StreamForward) error {
	m.trackCall("AddStreamForward")
	if m.AddStreamForwardFunc != nil {
		return m.AddStreamForwardFunc(ctx, fwd)
	}
	return nil
}

func (m *MockStreamD) RemoveStreamForward(ctx context.Context, sourceID, sinkID string) error {
	m.trackCall("RemoveStreamForward")
	if m.RemoveStreamForwardFunc != nil {
		return m.RemoveStreamForwardFunc(ctx, sourceID, sinkID)
	}
	return nil
}

func (m *MockStreamD) ListStreamServers(ctx context.Context) ([]StreamServer, error) {
	m.trackCall("ListStreamServers")
	if m.ListStreamServersFunc != nil {
		return m.ListStreamServersFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) ListStreamPlayers(ctx context.Context) ([]StreamPlayer, error) {
	m.trackCall("ListStreamPlayers")
	if m.ListStreamPlayersFunc != nil {
		return m.ListStreamPlayersFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) PlayerOpen(ctx context.Context, playerID string, url string) error {
	m.trackCall("PlayerOpen")
	if m.PlayerOpenFunc != nil {
		return m.PlayerOpenFunc(ctx, playerID, url)
	}
	return nil
}

func (m *MockStreamD) PlayerClose(ctx context.Context, playerID string) error {
	m.trackCall("PlayerClose")
	if m.PlayerCloseFunc != nil {
		return m.PlayerCloseFunc(ctx, playerID)
	}
	return nil
}

func (m *MockStreamD) PlayerSetPause(ctx context.Context, playerID string, paused bool) error {
	m.trackCall("PlayerSetPause")
	if m.PlayerSetPauseFunc != nil {
		return m.PlayerSetPauseFunc(ctx, playerID, paused)
	}
	return nil
}

func (m *MockStreamD) PlayerGetLag(ctx context.Context, playerID string) (float64, error) {
	m.trackCall("PlayerGetLag")
	if m.PlayerGetLagFunc != nil {
		return m.PlayerGetLagFunc(ctx, playerID)
	}
	return 0, nil
}

func (m *MockStreamD) SubscribeToChatMessages(ctx context.Context, since int64, limit int32, streamID string) (<-chan ChatMessage, error) {
	m.trackCall("SubscribeToChatMessages")
	if m.SubscribeToChatMessagesFunc != nil {
		return m.SubscribeToChatMessagesFunc(ctx, since, limit, streamID)
	}
	ch := make(chan ChatMessage)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SendChatMessage(ctx context.Context, platform, accountID, message string) error {
	m.trackCall("SendChatMessage")
	if m.SendChatMessageFunc != nil {
		return m.SendChatMessageFunc(ctx, platform, accountID, message)
	}
	return nil
}

func (m *MockStreamD) ListProfiles(ctx context.Context) ([]Profile, error) {
	m.trackCall("ListProfiles")
	if m.ListProfilesFunc != nil {
		return m.ListProfilesFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) ApplyProfile(ctx context.Context, streamID StreamIDFullyQualified, profileName string) error {
	m.trackCall("ApplyProfile")
	if m.ApplyProfileFunc != nil {
		return m.ApplyProfileFunc(ctx, streamID, profileName)
	}
	return nil
}

func (m *MockStreamD) GetAccounts(ctx context.Context, platformIDs []string) ([]Account, error) {
	m.trackCall("GetAccounts")
	if m.GetAccountsFunc != nil {
		return m.GetAccountsFunc(ctx, platformIDs)
	}
	return nil, nil
}

func (m *MockStreamD) GetVariable(ctx context.Context, key string) ([]byte, error) {
	m.trackCall("GetVariable")
	if m.GetVariableFunc != nil {
		return m.GetVariableFunc(ctx, key)
	}
	return nil, nil
}

func (m *MockStreamD) SetVariable(ctx context.Context, key string, value []byte) error {
	m.trackCall("SetVariable")
	if m.SetVariableFunc != nil {
		return m.SetVariableFunc(ctx, key, value)
	}
	return nil
}

func (m *MockStreamD) SubscribeToVariable(ctx context.Context, key string) (<-chan []byte, error) {
	m.trackCall("SubscribeToVariable")
	if m.SubscribeToVariableFunc != nil {
		return m.SubscribeToVariableFunc(ctx, key)
	}
	ch := make(chan []byte)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) ResetCache(ctx context.Context) error {
	m.trackCall("ResetCache")
	if m.ResetCacheFunc != nil {
		return m.ResetCacheFunc(ctx)
	}
	return nil
}

func (m *MockStreamD) InitCache(ctx context.Context) error {
	m.trackCall("InitCache")
	if m.InitCacheFunc != nil {
		return m.InitCacheFunc(ctx)
	}
	return nil
}

func (m *MockStreamD) GetStreams(ctx context.Context) ([]Stream, error) {
	m.trackCall("GetStreams")
	if m.GetStreamsFunc != nil {
		return m.GetStreamsFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) CreateStream(ctx context.Context, platformID string, title string, description string, profile string) error {
	m.trackCall("CreateStream")
	if m.CreateStreamFunc != nil {
		return m.CreateStreamFunc(ctx, platformID, title, description, profile)
	}
	return nil
}

func (m *MockStreamD) DeleteStream(ctx context.Context, streamID StreamIDFullyQualified) error {
	m.trackCall("DeleteStream")
	if m.DeleteStreamFunc != nil {
		return m.DeleteStreamFunc(ctx, streamID)
	}
	return nil
}

func (m *MockStreamD) GetActiveStreamIDs(ctx context.Context) ([]StreamIDFullyQualified, error) {
	m.trackCall("GetActiveStreamIDs")
	if m.GetActiveStreamIDsFunc != nil {
		return m.GetActiveStreamIDsFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) StartStream(ctx context.Context, platID string, profileName string) error {
	m.trackCall("StartStream")
	if m.StartStreamFunc != nil {
		return m.StartStreamFunc(ctx, platID, profileName)
	}
	return nil
}

func (m *MockStreamD) EndStream(ctx context.Context, platID string) error {
	m.trackCall("EndStream")
	if m.EndStreamFunc != nil {
		return m.EndStreamFunc(ctx, platID)
	}
	return nil
}

func (m *MockStreamD) IsBackendEnabled(ctx context.Context, platformID string) (bool, error) {
	m.trackCall("IsBackendEnabled")
	if m.IsBackendEnabledFunc != nil {
		return m.IsBackendEnabledFunc(ctx, platformID)
	}
	return false, nil
}

func (m *MockStreamD) GetBackendInfo(ctx context.Context, platformID string) (*BackendInfo, error) {
	m.trackCall("GetBackendInfo")
	if m.GetBackendInfoFunc != nil {
		return m.GetBackendInfoFunc(ctx, platformID)
	}
	return &BackendInfo{}, nil
}

func (m *MockStreamD) GetPlatforms(ctx context.Context) ([]string, error) {
	m.trackCall("GetPlatforms")
	if m.GetPlatformsFunc != nil {
		return m.GetPlatformsFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) SetTitle(ctx context.Context, platID string, title string) error {
	m.trackCall("SetTitle")
	if m.SetTitleFunc != nil {
		return m.SetTitleFunc(ctx, platID, title)
	}
	return nil
}

func (m *MockStreamD) SetDescription(ctx context.Context, platID string, description string) error {
	m.trackCall("SetDescription")
	if m.SetDescriptionFunc != nil {
		return m.SetDescriptionFunc(ctx, platID, description)
	}
	return nil
}

func (m *MockStreamD) GetVariableHash(ctx context.Context, key string, hashType string) (string, error) {
	m.trackCall("GetVariableHash")
	if m.GetVariableHashFunc != nil {
		return m.GetVariableHashFunc(ctx, key, hashType)
	}
	return "", nil
}

func (m *MockStreamD) SubscribeToOAuthRequests(ctx context.Context) (<-chan OAuthRequest, error) {
	m.trackCall("SubscribeToOAuthRequests")
	if m.SubscribeToOAuthRequestsFunc != nil {
		return m.SubscribeToOAuthRequestsFunc(ctx)
	}
	ch := make(chan OAuthRequest)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubmitOAuthCode(ctx context.Context, requestID string, code string) error {
	m.trackCall("SubmitOAuthCode")
	if m.SubmitOAuthCodeFunc != nil {
		return m.SubmitOAuthCodeFunc(ctx, requestID, code)
	}
	return nil
}

func (m *MockStreamD) StartStreamServer(ctx context.Context, config StreamServer) error {
	m.trackCall("StartStreamServer")
	if m.StartStreamServerFunc != nil {
		return m.StartStreamServerFunc(ctx, config)
	}
	return nil
}

func (m *MockStreamD) StopStreamServer(ctx context.Context, serverID string) error {
	m.trackCall("StopStreamServer")
	if m.StopStreamServerFunc != nil {
		return m.StopStreamServerFunc(ctx, serverID)
	}
	return nil
}

func (m *MockStreamD) UpdateStreamSink(ctx context.Context, sink StreamSink) error {
	m.trackCall("UpdateStreamSink")
	if m.UpdateStreamSinkFunc != nil {
		return m.UpdateStreamSinkFunc(ctx, sink)
	}
	return nil
}

func (m *MockStreamD) GetStreamSinkConfig(ctx context.Context, sinkID string) (*StreamSinkConfig, error) {
	m.trackCall("GetStreamSinkConfig")
	if m.GetStreamSinkConfigFunc != nil {
		return m.GetStreamSinkConfigFunc(ctx, sinkID)
	}
	return &StreamSinkConfig{}, nil
}

func (m *MockStreamD) UpdateStreamForward(ctx context.Context, fwd StreamForward) error {
	m.trackCall("UpdateStreamForward")
	if m.UpdateStreamForwardFunc != nil {
		return m.UpdateStreamForwardFunc(ctx, fwd)
	}
	return nil
}

func (m *MockStreamD) AddStreamPlayer(ctx context.Context, player StreamPlayer) error {
	m.trackCall("AddStreamPlayer")
	if m.AddStreamPlayerFunc != nil {
		return m.AddStreamPlayerFunc(ctx, player)
	}
	return nil
}

func (m *MockStreamD) RemoveStreamPlayer(ctx context.Context, playerID string) error {
	m.trackCall("RemoveStreamPlayer")
	if m.RemoveStreamPlayerFunc != nil {
		return m.RemoveStreamPlayerFunc(ctx, playerID)
	}
	return nil
}

func (m *MockStreamD) UpdateStreamPlayer(ctx context.Context, player StreamPlayer) error {
	m.trackCall("UpdateStreamPlayer")
	if m.UpdateStreamPlayerFunc != nil {
		return m.UpdateStreamPlayerFunc(ctx, player)
	}
	return nil
}

func (m *MockStreamD) GetStreamPlayer(ctx context.Context, playerID string) (*StreamPlayer, error) {
	m.trackCall("GetStreamPlayer")
	if m.GetStreamPlayerFunc != nil {
		return m.GetStreamPlayerFunc(ctx, playerID)
	}
	return &StreamPlayer{}, nil
}

func (m *MockStreamD) PlayerProcessTitle(ctx context.Context, playerID string, title string) (string, error) {
	m.trackCall("PlayerProcessTitle")
	if m.PlayerProcessTitleFunc != nil {
		return m.PlayerProcessTitleFunc(ctx, playerID, title)
	}
	return title, nil
}

func (m *MockStreamD) PlayerGetLink(ctx context.Context, playerID string) (string, error) {
	m.trackCall("PlayerGetLink")
	if m.PlayerGetLinkFunc != nil {
		return m.PlayerGetLinkFunc(ctx, playerID)
	}
	return "", nil
}

func (m *MockStreamD) PlayerIsEnded(ctx context.Context, playerID string) (bool, error) {
	m.trackCall("PlayerIsEnded")
	if m.PlayerIsEndedFunc != nil {
		return m.PlayerIsEndedFunc(ctx, playerID)
	}
	return false, nil
}

func (m *MockStreamD) PlayerGetPosition(ctx context.Context, playerID string) (float64, error) {
	m.trackCall("PlayerGetPosition")
	if m.PlayerGetPositionFunc != nil {
		return m.PlayerGetPositionFunc(ctx, playerID)
	}
	return 0, nil
}

func (m *MockStreamD) PlayerGetLength(ctx context.Context, playerID string) (float64, error) {
	m.trackCall("PlayerGetLength")
	if m.PlayerGetLengthFunc != nil {
		return m.PlayerGetLengthFunc(ctx, playerID)
	}
	return 0, nil
}

func (m *MockStreamD) PlayerSetSpeed(ctx context.Context, playerID string, speed float64) error {
	m.trackCall("PlayerSetSpeed")
	if m.PlayerSetSpeedFunc != nil {
		return m.PlayerSetSpeedFunc(ctx, playerID, speed)
	}
	return nil
}

func (m *MockStreamD) PlayerGetSpeed(ctx context.Context, playerID string) (float64, error) {
	m.trackCall("PlayerGetSpeed")
	if m.PlayerGetSpeedFunc != nil {
		return m.PlayerGetSpeedFunc(ctx, playerID)
	}
	return 1.0, nil
}

func (m *MockStreamD) PlayerStop(ctx context.Context, playerID string) error {
	m.trackCall("PlayerStop")
	if m.PlayerStopFunc != nil {
		return m.PlayerStopFunc(ctx, playerID)
	}
	return nil
}

func (m *MockStreamD) RemoveChatMessage(ctx context.Context, platID string, messageID string) error {
	m.trackCall("RemoveChatMessage")
	if m.RemoveChatMessageFunc != nil {
		return m.RemoveChatMessageFunc(ctx, platID, messageID)
	}
	return nil
}

func (m *MockStreamD) BanUser(ctx context.Context, platID string, userID string, reason string, durationSeconds int64) error {
	m.trackCall("BanUser")
	if m.BanUserFunc != nil {
		return m.BanUserFunc(ctx, platID, userID, reason, durationSeconds)
	}
	return nil
}

func (m *MockStreamD) InjectPlatformEvent(ctx context.Context, event ChatEvent) error {
	m.trackCall("InjectPlatformEvent")
	if m.InjectPlatformEventFunc != nil {
		return m.InjectPlatformEventFunc(ctx, event)
	}
	return nil
}

func (m *MockStreamD) Shoutout(ctx context.Context, platID string, targetUserName string) error {
	m.trackCall("Shoutout")
	if m.ShoutoutFunc != nil {
		return m.ShoutoutFunc(ctx, platID, targetUserName)
	}
	return nil
}

func (m *MockStreamD) RaidTo(ctx context.Context, platID string, targetChannel string) error {
	m.trackCall("RaidTo")
	if m.RaidToFunc != nil {
		return m.RaidToFunc(ctx, platID, targetChannel)
	}
	return nil
}

func (m *MockStreamD) GetPeerIDs(ctx context.Context) ([]string, error) {
	m.trackCall("GetPeerIDs")
	if m.GetPeerIDsFunc != nil {
		return m.GetPeerIDsFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) AddTimer(ctx context.Context, timer Timer) error {
	m.trackCall("AddTimer")
	if m.AddTimerFunc != nil {
		return m.AddTimerFunc(ctx, timer)
	}
	return nil
}

func (m *MockStreamD) RemoveTimer(ctx context.Context, timerID string) error {
	m.trackCall("RemoveTimer")
	if m.RemoveTimerFunc != nil {
		return m.RemoveTimerFunc(ctx, timerID)
	}
	return nil
}

func (m *MockStreamD) ListTimers(ctx context.Context) ([]Timer, error) {
	m.trackCall("ListTimers")
	if m.ListTimersFunc != nil {
		return m.ListTimersFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) ListTriggerRules(ctx context.Context) ([]TriggerRule, error) {
	m.trackCall("ListTriggerRules")
	if m.ListTriggerRulesFunc != nil {
		return m.ListTriggerRulesFunc(ctx)
	}
	return nil, nil
}

func (m *MockStreamD) AddTriggerRule(ctx context.Context, rule TriggerRule) error {
	m.trackCall("AddTriggerRule")
	if m.AddTriggerRuleFunc != nil {
		return m.AddTriggerRuleFunc(ctx, rule)
	}
	return nil
}

func (m *MockStreamD) RemoveTriggerRule(ctx context.Context, ruleID string) error {
	m.trackCall("RemoveTriggerRule")
	if m.RemoveTriggerRuleFunc != nil {
		return m.RemoveTriggerRuleFunc(ctx, ruleID)
	}
	return nil
}

func (m *MockStreamD) UpdateTriggerRule(ctx context.Context, rule TriggerRule) error {
	m.trackCall("UpdateTriggerRule")
	if m.UpdateTriggerRuleFunc != nil {
		return m.UpdateTriggerRuleFunc(ctx, rule)
	}
	return nil
}

func (m *MockStreamD) SubmitEvent(ctx context.Context, event Event) error {
	m.trackCall("SubmitEvent")
	if m.SubmitEventFunc != nil {
		return m.SubmitEventFunc(ctx, event)
	}
	return nil
}

func (m *MockStreamD) LLMGenerate(ctx context.Context, prompt string) (string, error) {
	m.trackCall("LLMGenerate")
	if m.LLMGenerateFunc != nil {
		return m.LLMGenerateFunc(ctx, prompt)
	}
	return "", nil
}

func (m *MockStreamD) Restart(ctx context.Context) error {
	m.trackCall("Restart")
	if m.RestartFunc != nil {
		return m.RestartFunc(ctx)
	}
	return nil
}

func (m *MockStreamD) ReinitStreamControllers(ctx context.Context) error {
	m.trackCall("ReinitStreamControllers")
	if m.ReinitStreamControllersFunc != nil {
		return m.ReinitStreamControllersFunc(ctx)
	}
	return nil
}

func (m *MockStreamD) SubscribeToConfigChanges(ctx context.Context) (<-chan string, error) {
	m.trackCall("SubscribeToConfigChanges")
	if m.SubscribeToConfigChangesFunc != nil {
		return m.SubscribeToConfigChangesFunc(ctx)
	}
	ch := make(chan string)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamsChanges(ctx context.Context) (<-chan Stream, error) {
	m.trackCall("SubscribeToStreamsChanges")
	if m.SubscribeToStreamsChangesFunc != nil {
		return m.SubscribeToStreamsChangesFunc(ctx)
	}
	ch := make(chan Stream)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamServersChanges(ctx context.Context) (<-chan StreamServer, error) {
	m.trackCall("SubscribeToStreamServersChanges")
	if m.SubscribeToStreamServersChangesFunc != nil {
		return m.SubscribeToStreamServersChangesFunc(ctx)
	}
	ch := make(chan StreamServer)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamSourcesChanges(ctx context.Context) (<-chan StreamSource, error) {
	m.trackCall("SubscribeToStreamSourcesChanges")
	if m.SubscribeToStreamSourcesChangesFunc != nil {
		return m.SubscribeToStreamSourcesChangesFunc(ctx)
	}
	ch := make(chan StreamSource)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamSinksChanges(ctx context.Context) (<-chan StreamSink, error) {
	m.trackCall("SubscribeToStreamSinksChanges")
	if m.SubscribeToStreamSinksChangesFunc != nil {
		return m.SubscribeToStreamSinksChangesFunc(ctx)
	}
	ch := make(chan StreamSink)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamForwardsChanges(ctx context.Context) (<-chan StreamForward, error) {
	m.trackCall("SubscribeToStreamForwardsChanges")
	if m.SubscribeToStreamForwardsChangesFunc != nil {
		return m.SubscribeToStreamForwardsChangesFunc(ctx)
	}
	ch := make(chan StreamForward)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) SubscribeToStreamPlayersChanges(ctx context.Context) (<-chan StreamPlayer, error) {
	m.trackCall("SubscribeToStreamPlayersChanges")
	if m.SubscribeToStreamPlayersChangesFunc != nil {
		return m.SubscribeToStreamPlayersChangesFunc(ctx)
	}
	ch := make(chan StreamPlayer)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockStreamD) WaitForStreamPublisher(ctx context.Context, sourceID string) error {
	m.trackCall("WaitForStreamPublisher")
	if m.WaitForStreamPublisherFunc != nil {
		return m.WaitForStreamPublisherFunc(ctx, sourceID)
	}
	<-ctx.Done()
	return ctx.Err()
}

func (m *MockStreamD) PlayerEndChan(ctx context.Context, playerID string) (<-chan struct{}, error) {
	m.trackCall("PlayerEndChan")
	if m.PlayerEndChanFunc != nil {
		return m.PlayerEndChanFunc(ctx, playerID)
	}
	ch := make(chan struct{})
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

// Compile-time interface check
var _ StreamDBackend = (*MockStreamD)(nil)
