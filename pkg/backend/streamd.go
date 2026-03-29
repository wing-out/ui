package backend

import (
	"context"
)

// StreamDBackend abstracts the StreamD stream control daemon.
// It can be implemented as embedded (in-process) or remote (gRPC proxy).
type StreamDBackend interface {
	// Ping sends a ping with payload and returns the response.
	Ping(ctx context.Context, payload string) (string, error)

	// SetLoggingLevel sets the logging level.
	SetLoggingLevel(ctx context.Context, level int) error

	// GetLoggingLevel returns the current logging level.
	GetLoggingLevel(ctx context.Context) (int, error)

	// GetConfig returns the current configuration as YAML.
	GetConfig(ctx context.Context) (string, error)

	// SetConfig updates the configuration from YAML.
	SetConfig(ctx context.Context, configYAML string) error

	// SaveConfig persists the current configuration to disk.
	SaveConfig(ctx context.Context) error

	// SetStreamActive activates or deactivates a stream.
	SetStreamActive(ctx context.Context, streamID StreamIDFullyQualified, active bool) error

	// GetStreamStatus returns the status of a stream.
	GetStreamStatus(ctx context.Context, streamID StreamIDFullyQualified, noCache bool) (*StreamStatus, error)

	// ListStreamSources returns all stream sources.
	ListStreamSources(ctx context.Context) ([]StreamSource, error)

	// AddStreamSource adds a new stream source.
	AddStreamSource(ctx context.Context, url string) error

	// RemoveStreamSource removes a stream source.
	RemoveStreamSource(ctx context.Context, id string) error

	// ListStreamSinks returns all stream sinks.
	ListStreamSinks(ctx context.Context) ([]StreamSink, error)

	// AddStreamSink adds a new stream sink.
	AddStreamSink(ctx context.Context, sink StreamSink) error

	// RemoveStreamSink removes a stream sink.
	RemoveStreamSink(ctx context.Context, id string) error

	// ListStreamForwards returns all stream forwards.
	ListStreamForwards(ctx context.Context) ([]StreamForward, error)

	// AddStreamForward adds a new stream forward.
	AddStreamForward(ctx context.Context, fwd StreamForward) error

	// RemoveStreamForward removes a stream forward.
	RemoveStreamForward(ctx context.Context, sourceID, sinkID string) error

	// ListStreamServers returns all running stream servers.
	ListStreamServers(ctx context.Context) ([]StreamServer, error)

	// ListStreamPlayers returns all stream players.
	ListStreamPlayers(ctx context.Context) ([]StreamPlayer, error)

	// PlayerOpen opens a URL in a player.
	PlayerOpen(ctx context.Context, playerID string, url string) error

	// PlayerClose closes a player.
	PlayerClose(ctx context.Context, playerID string) error

	// PlayerSetPause sets the pause state of a player.
	PlayerSetPause(ctx context.Context, playerID string, paused bool) error

	// PlayerGetLag returns player lag in seconds.
	PlayerGetLag(ctx context.Context, playerID string) (float64, error)

	// SubscribeToChatMessages returns a channel of chat messages.
	// If streamID is non-empty, only messages for that stream are returned.
	SubscribeToChatMessages(ctx context.Context, since int64, limit int32, streamID string) (<-chan ChatMessage, error)

	// SendChatMessage sends a chat message to a platform.
	SendChatMessage(ctx context.Context, platform, accountID, message string) error

	// ListProfiles returns all streaming profiles.
	ListProfiles(ctx context.Context) ([]Profile, error)

	// ApplyProfile applies a profile to a stream.
	ApplyProfile(ctx context.Context, streamID StreamIDFullyQualified, profileName string) error

	// GetAccounts returns accounts for the given platform IDs.
	GetAccounts(ctx context.Context, platformIDs []string) ([]Account, error)

	// GetVariable returns a variable value by key.
	GetVariable(ctx context.Context, key string) ([]byte, error)

	// SetVariable sets a variable value by key.
	SetVariable(ctx context.Context, key string, value []byte) error

	// SubscribeToVariable returns a channel that emits variable changes.
	SubscribeToVariable(ctx context.Context, key string) (<-chan []byte, error)

	// ResetCache resets the backend cache.
	ResetCache(ctx context.Context) error

	// InitCache initializes the backend cache.
	InitCache(ctx context.Context) error

	// GetStreams returns all streams.
	GetStreams(ctx context.Context) ([]Stream, error)

	// CreateStream creates a new stream.
	CreateStream(ctx context.Context, platformID string, title string, description string, profile string) error

	// DeleteStream deletes a stream.
	DeleteStream(ctx context.Context, streamID StreamIDFullyQualified) error

	// GetActiveStreamIDs returns all active stream IDs.
	GetActiveStreamIDs(ctx context.Context) ([]StreamIDFullyQualified, error)

	// StartStream starts a stream on a platform with a profile.
	StartStream(ctx context.Context, platID string, profileName string) error

	// EndStream ends a stream on a platform.
	EndStream(ctx context.Context, platID string) error

	// IsBackendEnabled checks if a backend platform is enabled.
	IsBackendEnabled(ctx context.Context, platformID string) (bool, error)

	// GetBackendInfo returns information about a backend platform.
	GetBackendInfo(ctx context.Context, platformID string) (*BackendInfo, error)

	// GetPlatforms returns all available platform IDs.
	GetPlatforms(ctx context.Context) ([]string, error)

	// SetTitle sets the title for a platform stream.
	SetTitle(ctx context.Context, platID string, title string) error

	// SetDescription sets the description for a platform stream.
	SetDescription(ctx context.Context, platID string, description string) error

	// GetVariableHash returns the hash of a variable value.
	GetVariableHash(ctx context.Context, key string, hashType string) (string, error)

	// SubscribeToOAuthRequests returns a channel that emits OAuth requests.
	SubscribeToOAuthRequests(ctx context.Context) (<-chan OAuthRequest, error)

	// SubmitOAuthCode submits an OAuth authorization code for a request.
	SubmitOAuthCode(ctx context.Context, requestID string, code string) error

	// StartStreamServer starts a stream server with the given config.
	StartStreamServer(ctx context.Context, config StreamServer) error

	// StopStreamServer stops a stream server by ID.
	StopStreamServer(ctx context.Context, serverID string) error

	// UpdateStreamSink updates an existing stream sink.
	UpdateStreamSink(ctx context.Context, sink StreamSink) error

	// GetStreamSinkConfig returns the configuration for a stream sink.
	GetStreamSinkConfig(ctx context.Context, sinkID string) (*StreamSinkConfig, error)

	// UpdateStreamForward updates an existing stream forward.
	UpdateStreamForward(ctx context.Context, fwd StreamForward) error

	// AddStreamPlayer adds a new stream player.
	AddStreamPlayer(ctx context.Context, player StreamPlayer) error

	// RemoveStreamPlayer removes a stream player.
	RemoveStreamPlayer(ctx context.Context, playerID string) error

	// UpdateStreamPlayer updates an existing stream player.
	UpdateStreamPlayer(ctx context.Context, player StreamPlayer) error

	// GetStreamPlayer returns a stream player by ID.
	GetStreamPlayer(ctx context.Context, playerID string) (*StreamPlayer, error)

	// PlayerProcessTitle processes a title for a player and returns the result.
	PlayerProcessTitle(ctx context.Context, playerID string, title string) (string, error)

	// PlayerGetLink returns the current link for a player.
	PlayerGetLink(ctx context.Context, playerID string) (string, error)

	// PlayerIsEnded checks if a player has finished playback.
	PlayerIsEnded(ctx context.Context, playerID string) (bool, error)

	// PlayerGetPosition returns the current position in seconds.
	PlayerGetPosition(ctx context.Context, playerID string) (float64, error)

	// PlayerGetLength returns the total length in seconds.
	PlayerGetLength(ctx context.Context, playerID string) (float64, error)

	// PlayerSetSpeed sets the playback speed.
	PlayerSetSpeed(ctx context.Context, playerID string, speed float64) error

	// PlayerGetSpeed returns the current playback speed.
	PlayerGetSpeed(ctx context.Context, playerID string) (float64, error)

	// PlayerStop stops a player.
	PlayerStop(ctx context.Context, playerID string) error

	// RemoveChatMessage removes a chat message from a platform.
	RemoveChatMessage(ctx context.Context, platID string, messageID string) error

	// BanUser bans a user on a platform.
	BanUser(ctx context.Context, platID string, userID string, reason string, durationSeconds int64) error

	// InjectPlatformEvent injects a platform chat event.
	InjectPlatformEvent(ctx context.Context, event ChatEvent) error

	// Shoutout sends a shoutout on a platform.
	Shoutout(ctx context.Context, platID string, targetUserName string) error

	// RaidTo starts a raid to a target channel.
	RaidTo(ctx context.Context, platID string, targetChannel string) error

	// GetPeerIDs returns the list of peer IDs.
	GetPeerIDs(ctx context.Context) ([]string, error)

	// AddTimer adds a new timer.
	AddTimer(ctx context.Context, timer Timer) error

	// RemoveTimer removes a timer by ID.
	RemoveTimer(ctx context.Context, timerID string) error

	// ListTimers returns all timers.
	ListTimers(ctx context.Context) ([]Timer, error)

	// ListTriggerRules returns all trigger rules.
	ListTriggerRules(ctx context.Context) ([]TriggerRule, error)

	// AddTriggerRule adds a new trigger rule.
	AddTriggerRule(ctx context.Context, rule TriggerRule) error

	// RemoveTriggerRule removes a trigger rule by ID.
	RemoveTriggerRule(ctx context.Context, ruleID string) error

	// UpdateTriggerRule updates an existing trigger rule.
	UpdateTriggerRule(ctx context.Context, rule TriggerRule) error

	// SubmitEvent submits a generic event.
	SubmitEvent(ctx context.Context, event Event) error

	// LLMGenerate generates text using an LLM.
	LLMGenerate(ctx context.Context, prompt string) (string, error)

	// Restart restarts the StreamD backend.
	Restart(ctx context.Context) error

	// ReinitStreamControllers reinitializes all stream controllers.
	ReinitStreamControllers(ctx context.Context) error

	// SubscribeToConfigChanges returns a channel that emits config change notifications.
	SubscribeToConfigChanges(ctx context.Context) (<-chan string, error)

	// SubscribeToStreamsChanges returns a channel that emits stream changes.
	SubscribeToStreamsChanges(ctx context.Context) (<-chan Stream, error)

	// SubscribeToStreamServersChanges returns a channel that emits stream server changes.
	SubscribeToStreamServersChanges(ctx context.Context) (<-chan StreamServer, error)

	// SubscribeToStreamSourcesChanges returns a channel that emits stream source changes.
	SubscribeToStreamSourcesChanges(ctx context.Context) (<-chan StreamSource, error)

	// SubscribeToStreamSinksChanges returns a channel that emits stream sink changes.
	SubscribeToStreamSinksChanges(ctx context.Context) (<-chan StreamSink, error)

	// SubscribeToStreamForwardsChanges returns a channel that emits stream forward changes.
	SubscribeToStreamForwardsChanges(ctx context.Context) (<-chan StreamForward, error)

	// SubscribeToStreamPlayersChanges returns a channel that emits stream player changes.
	SubscribeToStreamPlayersChanges(ctx context.Context) (<-chan StreamPlayer, error)

	// WaitForStreamPublisher blocks until a stream publisher connects for the given source.
	WaitForStreamPublisher(ctx context.Context, sourceID string) error

	// PlayerEndChan returns a channel that is closed when a player finishes.
	PlayerEndChan(ctx context.Context, playerID string) (<-chan struct{}, error)
}
