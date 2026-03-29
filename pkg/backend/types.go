package backend

import (
	"time"
)

// StreamStatus represents the status of a stream on a platform.
type StreamStatus struct {
	IsActive     bool
	StartedAt    *time.Time
	CustomData   string
	ViewersCount *uint64
}

// BitRateInfo contains bitrate information for a single track type.
type BitRateInfo struct {
	Audio uint64
	Video uint64
	Other uint64
}

// BitRates contains input, encoded, and output bitrate info.
type BitRates struct {
	InputBitRate   BitRateInfo
	EncodedBitRate BitRateInfo
	OutputBitRate  BitRateInfo
}

// TrackLatencies contains latency info for a single track.
type TrackLatencies struct {
	PreTranscodingUs     uint64
	TranscodingUs        uint64
	TranscodedPreSendUs  uint64
	SendingUs            uint64
}

// Latencies contains latency info for audio and video.
type Latencies struct {
	Audio TrackLatencies
	Video TrackLatencies
}

// StreamQuality represents quality metrics for a stream.
type StreamQuality struct {
	Continuity float64
	Overlap    float64
	FrameRate  float64
	InvalidDTS uint64
}

// QualityReport contains quality for audio and video.
type QualityReport struct {
	Audio StreamQuality
	Video StreamQuality
}

// NodeCounters contains pipeline node counters.
type NodeCounters struct {
	ReceivedPackets  uint64
	ReceivedFrames   uint64
	ProcessedPackets uint64
	ProcessedFrames  uint64
	MissedPackets    uint64
	MissedFrames     uint64
	GeneratedPackets uint64
	GeneratedFrames  uint64
	SentPackets      uint64
	SentFrames       uint64
}

// Stats contains pipeline statistics.
type Stats struct {
	NodeCounters NodeCounters
}

// InputInfo contains information about an input source.
type InputInfo struct {
	ID         uint64
	Priority   uint64
	Num        uint64
	URL        string
	IsActive   bool
	Suppressed bool
}

// TranscoderConfig configures the transcoder.
type TranscoderConfig struct {
	AudioCodec     string
	AudioBitRate   uint64
	AudioSampleRate uint32
	VideoCodec     string
	VideoBitRate   uint64
	VideoWidth     uint32
	VideoHeight    uint32
}

// SenderTemplate configures an output destination.
type SenderTemplate struct {
	URLTemplate                 string
	RetryOutputTimeoutOnFailure time.Duration
}

// CurrentOutput contains information about the current output.
type CurrentOutput struct {
	ID         uint64
	Config     TranscoderConfig
	MaxBitRate uint64
}

// SenderProps contains output switching properties.
type SenderProps struct {
	Config     TranscoderConfig
	MaxBitRate uint64
}

// AutoBitRateVideoConfig configures auto-bitrate for video.
type AutoBitRateVideoConfig struct {
	Enabled     bool
	MinHeight   uint32
	MaxHeight   uint32
	AutoBypass  bool
}

// MonitorRequest is a request to start monitoring.
type MonitorRequest struct {
	EventTypes []string
}

// MonitorEvent is an event from the monitoring stream.
type MonitorEvent struct {
	EventType string
	Timestamp int64
	Data      []byte
}

// SRTStats contains SRT protocol statistics.
type SRTStats struct {
	MsRTT            float64
	MbpsBandwidth    float64
	PktSndLoss       int64
	PktRcvLoss       int64
	PktRetrans       int64
	PktSndDrop       int64
	PktRcvDrop       int64
	MbpsSendRate     float64
	MbpsRecvRate     float64
	PktFlightSize    int64
	PktSent          int64
	PktRecv          int64
	PktSendLoss      int64
	PktRecvLoss      int64
	PktSendDrop      int64
	PktRecvDrop      int64
	BytesSent        int64
	BytesRecv        int64
	BytesSendDrop    int64
	BytesRecvDrop    int64
	RTTMS            float64
	BandwidthMbps    float64
	SendRateMbps     float64
	RecvRateMbps     float64
}

// StreamSource represents a stream input source.
type StreamSource struct {
	ID           string
	URL          string
	IsActive     bool
	IsSuppressed bool
}

// StreamSink represents a stream output destination.
type StreamSink struct {
	ID            string
	Type          string
	URL           string
	Name          string
	EncoderConfig *EncoderConfig
}

// StreamForward represents a stream forwarding rule.
type StreamForward struct {
	SourceID string
	SinkID   string
	SinkType string
	Enabled  bool
	Quirks   *StreamForwardQuirks
}

// StreamServer represents a running stream server.
type StreamServer struct {
	ID         string
	Type       string
	ListenAddr string
}

// StreamPlayer represents a media player instance.
type StreamPlayer struct {
	ID       string
	Title    string
	Link     string
	Position float64
	Length   float64
	IsPaused bool
}

// Profile represents a streaming profile configuration.
type Profile struct {
	Name        string
	Description string
}

// ChatMessage represents a chat message.
type ChatMessage struct {
	ID             string
	Platform       string
	StreamID       string
	UserName       string
	Message        string
	Timestamp      int64
	EventType      string
	User           ChatUser
	MessageContent ChatMessageContent
}

// Account represents a platform account.
type Account struct {
	PlatformID string
	AccountID  string
	UserName   string
}

// StreamIDFullyQualified identifies a stream with platform and account.
type StreamIDFullyQualified struct {
	PlatformID string
	AccountID  string
	StreamID   string
}

// BackendMode represents the operating mode of the backend.
type BackendMode string

const (
	BackendModeEmbedded BackendMode = "embedded"
	BackendModeRemote   BackendMode = "remote"
	BackendModeHybrid   BackendMode = "hybrid"
)

// Stream represents a streaming session.
type Stream struct {
	ID          StreamIDFullyQualified
	IsActive    bool
	Title       string
	Description string
	Profile     string
}

// AccountInfo contains account information for a platform.
type AccountInfo struct {
	PlatformID string
	AccountID  string
	IsEnabled  bool
}

// BackendInfo contains information about a streaming backend/platform.
type BackendInfo struct {
	PlatformID   string
	Capabilities []string
}

// StreamSinkConfig contains configuration for a stream sink.
type StreamSinkConfig struct {
	URL           string
	EncoderConfig *EncoderConfig
}

// EncoderConfig configures encoding parameters.
type EncoderConfig struct {
	AudioCodec   string
	VideoCodec   string
	AudioBitrate uint64
	VideoBitrate uint64
	VideoWidth   uint32
	VideoHeight  uint32
}

// StreamForwardQuirks contains quirks/tweaks for stream forwarding.
type StreamForwardQuirks struct {
	RestartOnError                  bool
	PlatformRecognitionWaitSeconds uint32
}

// StreamForwardDetail contains detailed stream forward information.
type StreamForwardDetail struct {
	SourceID string
	SinkID   string
	SinkType string
	Enabled  bool
	Quirks   *StreamForwardQuirks
}

// Timer represents a periodic action trigger.
type Timer struct {
	ID              string
	IntervalSeconds uint32
	Action          Action
}

// Action represents an action to be performed.
type Action struct {
	Type   string
	Params map[string]string
}

// TriggerRule defines a rule that triggers an action on an event.
type TriggerRule struct {
	ID         string
	EventQuery EventQuery
	Action     Action
	Enabled    bool
}

// EventQuery describes a query to match events.
type EventQuery struct {
	EventType string
	Filter    string
}

// Event represents a generic event.
type Event struct {
	Type string
	Data []byte
}

// ChatEvent represents a full chat event from chatwebhook.
type ChatEvent struct {
	ID                string
	CreatedAtUnixNano int64
	EventType         string
	Platform          string
	User              ChatUser
	TargetUser        *ChatUser
	MessageContent    *ChatMessageContent
	Money             *Money
}

// ChatUser represents a chat user.
type ChatUser struct {
	ID           string
	Slug         string
	Name         string
	NameReadable string
}

// ChatMessageContent represents message content in a chat event.
type ChatMessageContent struct {
	Content    string
	FormatType string
	InReplyTo  string
}

// Money represents a monetary amount.
type Money struct {
	Currency string
	Amount   float64
}

// OAuthRequest represents an OAuth authorization request.
type OAuthRequest struct {
	RequestID  string
	AuthURL    string
	PlatformID string
}

// VariableChange represents a change to a variable.
type VariableChange struct {
	Key   string
	Value []byte
}

// PlayerConfig contains player configuration.
type PlayerConfig struct {
	Type string
	URL  string
}

// PlayerPlaybackConfig contains playback configuration for a player.
type PlayerPlaybackConfig struct {
	Speed    float64
	IsPaused bool
}

// Diagnostics contains diagnostic information about the streaming system.
type Diagnostics struct {
	LatencyPreSending  *int32
	LatencySending     *int32
	FPSInput           *int32
	FPSOutput          *int32
	BitrateVideo       *int64
	PlayerLagMin       *int32
	PlayerLagMax       *int32
	PingRTT            *int32
	WiFiSSID           *string
	WiFiBSSID          *string
	WiFiRSSI           *int32
	Channels           []int32
	ViewersYoutube     *int32
	ViewersTwitch      *int32
	ViewersKick        *int32
	Signal             *int32
	StreamTime         *int32
	CPUUtilization     *float32
	MemoryUtilization  *float32
	Temperatures       []Temperature
}

// Temperature represents a temperature reading from a sensor.
type Temperature struct {
	Type string
	Temp float32
}

// Pipeline represents a streaming pipeline.
type Pipeline struct {
	ID          string
	Description string
}

// CustomOption represents a key-value custom option.
type CustomOption struct {
	Key   string
	Value string
}

// SRTFlagInt represents an SRT integer flag type.
type SRTFlagInt int

const (
	// SRTFlagIntLatency is the SRT latency flag.
	SRTFlagIntLatency SRTFlagInt = 1
)
