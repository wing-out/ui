package backend

import (
	"context"
	"time"
)

// FFStreamBackend abstracts the FFStream streaming engine.
// It can be implemented as embedded (in-process) or remote (gRPC proxy).
type FFStreamBackend interface {
	// Start starts the streaming pipeline with the given transcoder configuration.
	Start(ctx context.Context, cfg TranscoderConfig) error

	// Stop stops the streaming pipeline.
	Stop(ctx context.Context) error

	// Wait blocks until the streaming pipeline finishes.
	Wait(ctx context.Context) error

	// AddInput adds an input source to the pipeline.
	AddInput(ctx context.Context, url string, priority uint64) error

	// SetInputSuppressed enables or disables an input at the given priority/index.
	SetInputSuppressed(ctx context.Context, priority, idx uint64, suppressed bool) error

	// AddOutputTemplate adds an output destination template.
	AddOutputTemplate(ctx context.Context, tmpl SenderTemplate) error

	// SwitchOutputByProps dynamically switches output encoding properties.
	SwitchOutputByProps(ctx context.Context, props SenderProps) error

	// RemoveOutput removes an output by ID.
	RemoveOutput(ctx context.Context, id uint64) error

	// GetCurrentOutput returns the current output configuration.
	GetCurrentOutput(ctx context.Context) (*CurrentOutput, error)

	// GetStats returns pipeline statistics.
	GetStats(ctx context.Context) (*Stats, error)

	// GetBitRates returns current bitrate information.
	GetBitRates(ctx context.Context) (*BitRates, error)

	// GetLatencies returns pipeline latencies.
	GetLatencies(ctx context.Context) (*Latencies, error)

	// GetInputQuality returns input quality metrics.
	GetInputQuality(ctx context.Context) (*QualityReport, error)

	// GetOutputQuality returns output quality metrics.
	GetOutputQuality(ctx context.Context) (*QualityReport, error)

	// GetFPSFraction returns the current FPS as a fraction.
	GetFPSFraction(ctx context.Context) (num, den uint32, err error)

	// SetFPSFraction sets the target FPS as a fraction.
	SetFPSFraction(ctx context.Context, num, den uint32) error

	// GetInputsInfo returns information about all inputs.
	GetInputsInfo(ctx context.Context) ([]InputInfo, error)

	// SetAutoBitRateVideoConfig configures auto-bitrate for video.
	SetAutoBitRateVideoConfig(ctx context.Context, cfg AutoBitRateVideoConfig) error

	// GetAutoBitRateVideoConfig returns the current auto-bitrate config.
	GetAutoBitRateVideoConfig(ctx context.Context) (*AutoBitRateVideoConfig, error)

	// InjectSubtitles injects subtitle data into the stream.
	InjectSubtitles(ctx context.Context, data []byte, dur time.Duration) error

	// InjectData injects arbitrary data into the stream.
	InjectData(ctx context.Context, data []byte, dur time.Duration) error

	// GetOutputSRTStats returns SRT protocol statistics.
	GetOutputSRTStats(ctx context.Context, outputID int32) (*SRTStats, error)

	// Monitor starts monitoring pipeline events.
	Monitor(ctx context.Context, req MonitorRequest) (<-chan MonitorEvent, error)

	// SetLoggingLevel sets the logging level.
	SetLoggingLevel(ctx context.Context, level int) error

	// GetPipelines returns all pipelines.
	GetPipelines(ctx context.Context) ([]Pipeline, error)

	// GetVideoAutoBitRateCalculator returns the video auto bitrate calculator config.
	GetVideoAutoBitRateCalculator(ctx context.Context) ([]byte, error)

	// SetVideoAutoBitRateCalculator sets the video auto bitrate calculator config.
	SetVideoAutoBitRateCalculator(ctx context.Context, config []byte) error

	// GetSRTFlagInt returns the value of an SRT integer flag.
	GetSRTFlagInt(ctx context.Context, flag SRTFlagInt) (int64, error)

	// SetSRTFlagInt sets the value of an SRT integer flag.
	SetSRTFlagInt(ctx context.Context, flag SRTFlagInt, value int64) error

	// SetInputCustomOption sets a custom option on an input.
	SetInputCustomOption(ctx context.Context, inputID string, key string, value string) error

	// SetStopInput stops a specific input.
	SetStopInput(ctx context.Context, inputID string) error

	// End terminates the streaming engine.
	End(ctx context.Context) error

	// WaitChan returns a channel that is closed when the engine finishes.
	WaitChan(ctx context.Context) (<-chan struct{}, error)

	// InjectDiagnostics injects diagnostics data for a given duration.
	InjectDiagnostics(ctx context.Context, diagnostics *Diagnostics, durationNs uint64) error

	// FFSetLoggingLevel sets the FFmpeg-specific logging level.
	FFSetLoggingLevel(ctx context.Context, level int) error
}
