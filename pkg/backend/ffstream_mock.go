package backend

import (
	"context"
	"sync"
	"time"
)

// MockFFStream is a mock implementation of FFStreamBackend for testing.
type MockFFStream struct {
	mu sync.Mutex

	// Function fields for injectable behavior
	StartFunc                    func(ctx context.Context, cfg TranscoderConfig) error
	StopFunc                     func(ctx context.Context) error
	WaitFunc                     func(ctx context.Context) error
	AddInputFunc                 func(ctx context.Context, url string, priority uint64) error
	SetInputSuppressedFunc       func(ctx context.Context, priority, idx uint64, suppressed bool) error
	AddOutputTemplateFunc        func(ctx context.Context, tmpl SenderTemplate) error
	SwitchOutputByPropsFunc      func(ctx context.Context, props SenderProps) error
	RemoveOutputFunc             func(ctx context.Context, id uint64) error
	GetCurrentOutputFunc         func(ctx context.Context) (*CurrentOutput, error)
	GetStatsFunc                 func(ctx context.Context) (*Stats, error)
	GetBitRatesFunc              func(ctx context.Context) (*BitRates, error)
	GetLatenciesFunc             func(ctx context.Context) (*Latencies, error)
	GetInputQualityFunc          func(ctx context.Context) (*QualityReport, error)
	GetOutputQualityFunc         func(ctx context.Context) (*QualityReport, error)
	GetFPSFractionFunc           func(ctx context.Context) (num, den uint32, err error)
	SetFPSFractionFunc           func(ctx context.Context, num, den uint32) error
	GetInputsInfoFunc            func(ctx context.Context) ([]InputInfo, error)
	SetAutoBitRateVideoConfigFunc func(ctx context.Context, cfg AutoBitRateVideoConfig) error
	GetAutoBitRateVideoConfigFunc func(ctx context.Context) (*AutoBitRateVideoConfig, error)
	InjectSubtitlesFunc          func(ctx context.Context, data []byte, dur time.Duration) error
	InjectDataFunc               func(ctx context.Context, data []byte, dur time.Duration) error
	GetOutputSRTStatsFunc        func(ctx context.Context, outputID int32) (*SRTStats, error)
	MonitorFunc                         func(ctx context.Context, req MonitorRequest) (<-chan MonitorEvent, error)
	SetLoggingLevelFunc                 func(ctx context.Context, level int) error
	GetPipelinesFunc                    func(ctx context.Context) ([]Pipeline, error)
	GetVideoAutoBitRateCalculatorFunc   func(ctx context.Context) ([]byte, error)
	SetVideoAutoBitRateCalculatorFunc   func(ctx context.Context, config []byte) error
	GetSRTFlagIntFunc                   func(ctx context.Context, flag SRTFlagInt) (int64, error)
	SetSRTFlagIntFunc                   func(ctx context.Context, flag SRTFlagInt, value int64) error
	SetInputCustomOptionFunc            func(ctx context.Context, inputID string, key string, value string) error
	SetStopInputFunc                    func(ctx context.Context, inputID string) error
	EndFunc                             func(ctx context.Context) error
	WaitChanFunc                        func(ctx context.Context) (<-chan struct{}, error)
	InjectDiagnosticsFunc               func(ctx context.Context, diagnostics *Diagnostics, durationNs uint64) error
	FFSetLoggingLevelFunc               func(ctx context.Context, level int) error

	// Call tracking
	Calls map[string]int
}

// NewMockFFStream creates a new MockFFStream with default no-op implementations.
func NewMockFFStream() *MockFFStream {
	return &MockFFStream{
		Calls: make(map[string]int),
	}
}

func (m *MockFFStream) trackCall(name string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls[name]++
}

// CallCount returns the number of times a method was called.
func (m *MockFFStream) CallCount(name string) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.Calls[name]
}

// ResetCallCounts resets all call counters to zero.
func (m *MockFFStream) ResetCallCounts() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.Calls = make(map[string]int)
}

func (m *MockFFStream) Start(ctx context.Context, cfg TranscoderConfig) error {
	m.trackCall("Start")
	if m.StartFunc != nil {
		return m.StartFunc(ctx, cfg)
	}
	return nil
}

func (m *MockFFStream) Stop(ctx context.Context) error {
	m.trackCall("Stop")
	if m.StopFunc != nil {
		return m.StopFunc(ctx)
	}
	return nil
}

func (m *MockFFStream) Wait(ctx context.Context) error {
	m.trackCall("Wait")
	if m.WaitFunc != nil {
		return m.WaitFunc(ctx)
	}
	<-ctx.Done()
	return ctx.Err()
}

func (m *MockFFStream) AddInput(ctx context.Context, url string, priority uint64) error {
	m.trackCall("AddInput")
	if m.AddInputFunc != nil {
		return m.AddInputFunc(ctx, url, priority)
	}
	return nil
}

func (m *MockFFStream) SetInputSuppressed(ctx context.Context, priority, idx uint64, suppressed bool) error {
	m.trackCall("SetInputSuppressed")
	if m.SetInputSuppressedFunc != nil {
		return m.SetInputSuppressedFunc(ctx, priority, idx, suppressed)
	}
	return nil
}

func (m *MockFFStream) AddOutputTemplate(ctx context.Context, tmpl SenderTemplate) error {
	m.trackCall("AddOutputTemplate")
	if m.AddOutputTemplateFunc != nil {
		return m.AddOutputTemplateFunc(ctx, tmpl)
	}
	return nil
}

func (m *MockFFStream) SwitchOutputByProps(ctx context.Context, props SenderProps) error {
	m.trackCall("SwitchOutputByProps")
	if m.SwitchOutputByPropsFunc != nil {
		return m.SwitchOutputByPropsFunc(ctx, props)
	}
	return nil
}

func (m *MockFFStream) RemoveOutput(ctx context.Context, id uint64) error {
	m.trackCall("RemoveOutput")
	if m.RemoveOutputFunc != nil {
		return m.RemoveOutputFunc(ctx, id)
	}
	return nil
}

func (m *MockFFStream) GetCurrentOutput(ctx context.Context) (*CurrentOutput, error) {
	m.trackCall("GetCurrentOutput")
	if m.GetCurrentOutputFunc != nil {
		return m.GetCurrentOutputFunc(ctx)
	}
	return &CurrentOutput{}, nil
}

func (m *MockFFStream) GetStats(ctx context.Context) (*Stats, error) {
	m.trackCall("GetStats")
	if m.GetStatsFunc != nil {
		return m.GetStatsFunc(ctx)
	}
	return &Stats{}, nil
}

func (m *MockFFStream) GetBitRates(ctx context.Context) (*BitRates, error) {
	m.trackCall("GetBitRates")
	if m.GetBitRatesFunc != nil {
		return m.GetBitRatesFunc(ctx)
	}
	return &BitRates{}, nil
}

func (m *MockFFStream) GetLatencies(ctx context.Context) (*Latencies, error) {
	m.trackCall("GetLatencies")
	if m.GetLatenciesFunc != nil {
		return m.GetLatenciesFunc(ctx)
	}
	return &Latencies{}, nil
}

func (m *MockFFStream) GetInputQuality(ctx context.Context) (*QualityReport, error) {
	m.trackCall("GetInputQuality")
	if m.GetInputQualityFunc != nil {
		return m.GetInputQualityFunc(ctx)
	}
	return &QualityReport{}, nil
}

func (m *MockFFStream) GetOutputQuality(ctx context.Context) (*QualityReport, error) {
	m.trackCall("GetOutputQuality")
	if m.GetOutputQualityFunc != nil {
		return m.GetOutputQualityFunc(ctx)
	}
	return &QualityReport{}, nil
}

func (m *MockFFStream) GetFPSFraction(ctx context.Context) (uint32, uint32, error) {
	m.trackCall("GetFPSFraction")
	if m.GetFPSFractionFunc != nil {
		return m.GetFPSFractionFunc(ctx)
	}
	return 30, 1, nil
}

func (m *MockFFStream) SetFPSFraction(ctx context.Context, num, den uint32) error {
	m.trackCall("SetFPSFraction")
	if m.SetFPSFractionFunc != nil {
		return m.SetFPSFractionFunc(ctx, num, den)
	}
	return nil
}

func (m *MockFFStream) GetInputsInfo(ctx context.Context) ([]InputInfo, error) {
	m.trackCall("GetInputsInfo")
	if m.GetInputsInfoFunc != nil {
		return m.GetInputsInfoFunc(ctx)
	}
	return nil, nil
}

func (m *MockFFStream) SetAutoBitRateVideoConfig(ctx context.Context, cfg AutoBitRateVideoConfig) error {
	m.trackCall("SetAutoBitRateVideoConfig")
	if m.SetAutoBitRateVideoConfigFunc != nil {
		return m.SetAutoBitRateVideoConfigFunc(ctx, cfg)
	}
	return nil
}

func (m *MockFFStream) GetAutoBitRateVideoConfig(ctx context.Context) (*AutoBitRateVideoConfig, error) {
	m.trackCall("GetAutoBitRateVideoConfig")
	if m.GetAutoBitRateVideoConfigFunc != nil {
		return m.GetAutoBitRateVideoConfigFunc(ctx)
	}
	return &AutoBitRateVideoConfig{}, nil
}

func (m *MockFFStream) InjectSubtitles(ctx context.Context, data []byte, dur time.Duration) error {
	m.trackCall("InjectSubtitles")
	if m.InjectSubtitlesFunc != nil {
		return m.InjectSubtitlesFunc(ctx, data, dur)
	}
	return nil
}

func (m *MockFFStream) InjectData(ctx context.Context, data []byte, dur time.Duration) error {
	m.trackCall("InjectData")
	if m.InjectDataFunc != nil {
		return m.InjectDataFunc(ctx, data, dur)
	}
	return nil
}

func (m *MockFFStream) GetOutputSRTStats(ctx context.Context, outputID int32) (*SRTStats, error) {
	m.trackCall("GetOutputSRTStats")
	if m.GetOutputSRTStatsFunc != nil {
		return m.GetOutputSRTStatsFunc(ctx, outputID)
	}
	return &SRTStats{}, nil
}

func (m *MockFFStream) Monitor(ctx context.Context, req MonitorRequest) (<-chan MonitorEvent, error) {
	m.trackCall("Monitor")
	if m.MonitorFunc != nil {
		return m.MonitorFunc(ctx, req)
	}
	ch := make(chan MonitorEvent)
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockFFStream) SetLoggingLevel(ctx context.Context, level int) error {
	m.trackCall("SetLoggingLevel")
	if m.SetLoggingLevelFunc != nil {
		return m.SetLoggingLevelFunc(ctx, level)
	}
	return nil
}

func (m *MockFFStream) GetPipelines(ctx context.Context) ([]Pipeline, error) {
	m.trackCall("GetPipelines")
	if m.GetPipelinesFunc != nil {
		return m.GetPipelinesFunc(ctx)
	}
	return nil, nil
}

func (m *MockFFStream) GetVideoAutoBitRateCalculator(ctx context.Context) ([]byte, error) {
	m.trackCall("GetVideoAutoBitRateCalculator")
	if m.GetVideoAutoBitRateCalculatorFunc != nil {
		return m.GetVideoAutoBitRateCalculatorFunc(ctx)
	}
	return nil, nil
}

func (m *MockFFStream) SetVideoAutoBitRateCalculator(ctx context.Context, config []byte) error {
	m.trackCall("SetVideoAutoBitRateCalculator")
	if m.SetVideoAutoBitRateCalculatorFunc != nil {
		return m.SetVideoAutoBitRateCalculatorFunc(ctx, config)
	}
	return nil
}

func (m *MockFFStream) GetSRTFlagInt(ctx context.Context, flag SRTFlagInt) (int64, error) {
	m.trackCall("GetSRTFlagInt")
	if m.GetSRTFlagIntFunc != nil {
		return m.GetSRTFlagIntFunc(ctx, flag)
	}
	return 0, nil
}

func (m *MockFFStream) SetSRTFlagInt(ctx context.Context, flag SRTFlagInt, value int64) error {
	m.trackCall("SetSRTFlagInt")
	if m.SetSRTFlagIntFunc != nil {
		return m.SetSRTFlagIntFunc(ctx, flag, value)
	}
	return nil
}

func (m *MockFFStream) SetInputCustomOption(ctx context.Context, inputID string, key string, value string) error {
	m.trackCall("SetInputCustomOption")
	if m.SetInputCustomOptionFunc != nil {
		return m.SetInputCustomOptionFunc(ctx, inputID, key, value)
	}
	return nil
}

func (m *MockFFStream) SetStopInput(ctx context.Context, inputID string) error {
	m.trackCall("SetStopInput")
	if m.SetStopInputFunc != nil {
		return m.SetStopInputFunc(ctx, inputID)
	}
	return nil
}

func (m *MockFFStream) End(ctx context.Context) error {
	m.trackCall("End")
	if m.EndFunc != nil {
		return m.EndFunc(ctx)
	}
	return nil
}

func (m *MockFFStream) WaitChan(ctx context.Context) (<-chan struct{}, error) {
	m.trackCall("WaitChan")
	if m.WaitChanFunc != nil {
		return m.WaitChanFunc(ctx)
	}
	ch := make(chan struct{})
	go func() {
		<-ctx.Done()
		close(ch)
	}()
	return ch, nil
}

func (m *MockFFStream) InjectDiagnostics(ctx context.Context, diagnostics *Diagnostics, durationNs uint64) error {
	m.trackCall("InjectDiagnostics")
	if m.InjectDiagnosticsFunc != nil {
		return m.InjectDiagnosticsFunc(ctx, diagnostics, durationNs)
	}
	return nil
}

func (m *MockFFStream) FFSetLoggingLevel(ctx context.Context, level int) error {
	m.trackCall("FFSetLoggingLevel")
	if m.FFSetLoggingLevelFunc != nil {
		return m.FFSetLoggingLevelFunc(ctx, level)
	}
	return nil
}

// Compile-time interface check
var _ FFStreamBackend = (*MockFFStream)(nil)
