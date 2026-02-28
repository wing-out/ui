package backend

import (
	"context"
	"fmt"
	"strconv"
	"time"

	avpipeline "github.com/xaionaro-go/avpipeline/protobuf/avpipeline"
	ffgrpc "github.com/xaionaro-go/ffstream/pkg/ffstreamserver/grpc/go/ffstream_grpc"
	"google.golang.org/grpc"
)

var _ FFStreamBackend = (*RemoteFFStream)(nil)

// RemoteFFStream implements FFStreamBackend by connecting to a native ffstream gRPC server.
type RemoteFFStream struct {
	conn   *grpc.ClientConn
	client ffgrpc.FFStreamClient
}

// NewRemoteFFStream dials the given address and returns a remote FFStream client.
// It probes the server to determine whether TLS is required, then connects accordingly.
func NewRemoteFFStream(addr string) (*RemoteFFStream, error) {
	creds := dialCredentials(addr)
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(creds))
	if err != nil {
		return nil, fmt.Errorf("dial ffstream at %s: %w", addr, err)
	}
	return &RemoteFFStream{
		conn:   conn,
		client: ffgrpc.NewFFStreamClient(conn),
	}, nil
}

// Close closes the gRPC connection.
func (r *RemoteFFStream) Close() error {
	return r.conn.Close()
}

func (r *RemoteFFStream) Start(ctx context.Context, cfg TranscoderConfig) error {
	return fmt.Errorf("Start is not supported for remote ffstream")
}

func (r *RemoteFFStream) Stop(ctx context.Context) error {
	return fmt.Errorf("Stop is not supported for remote ffstream")
}

func (r *RemoteFFStream) Wait(ctx context.Context) error {
	return fmt.Errorf("Wait is not supported for remote ffstream")
}

func (r *RemoteFFStream) AddInput(ctx context.Context, url string, priority uint64) error {
	return fmt.Errorf("AddInput is not supported for remote ffstream")
}

func (r *RemoteFFStream) SetInputSuppressed(ctx context.Context, priority, idx uint64, suppressed bool) error {
	_, err := r.client.SetInputSuppressed(ctx, &ffgrpc.SetInputSuppressedRequest{
		InputPriority: priority,
		InputNum:      idx,
		Suppressed:    suppressed,
	})
	return err
}

func (r *RemoteFFStream) AddOutputTemplate(ctx context.Context, tmpl SenderTemplate) error {
	return fmt.Errorf("AddOutputTemplate is not supported for remote ffstream")
}

func (r *RemoteFFStream) SwitchOutputByProps(ctx context.Context, props SenderProps) error {
	_, err := r.client.SwitchOutputByProps(ctx, &ffgrpc.SwitchOutputByPropsRequest{
		MaxBitRate: props.MaxBitRate,
	})
	return err
}

func (r *RemoteFFStream) RemoveOutput(ctx context.Context, id uint64) error {
	_, err := r.client.RemoveOutput(ctx, &ffgrpc.RemoveOutputRequest{
		Id: id,
	})
	return err
}

func (r *RemoteFFStream) GetCurrentOutput(ctx context.Context) (*CurrentOutput, error) {
	resp, err := r.client.GetCurrentOutput(ctx, &ffgrpc.GetCurrentOutputRequest{})
	if err != nil {
		return nil, err
	}
	return &CurrentOutput{
		ID:         resp.GetId(),
		MaxBitRate: resp.GetMaxBitRate(),
	}, nil
}

func (r *RemoteFFStream) GetStats(ctx context.Context) (*Stats, error) {
	resp, err := r.client.GetStats(ctx, &ffgrpc.GetStatsRequest{})
	if err != nil {
		return nil, err
	}
	nc := resp.GetNodeCounters()
	if nc == nil {
		return &Stats{}, nil
	}
	return &Stats{
		NodeCounters: nodeCountersFromAVProto(nc),
	}, nil
}

func (r *RemoteFFStream) GetBitRates(ctx context.Context) (*BitRates, error) {
	resp, err := r.client.GetBitRates(ctx, &ffgrpc.GetBitRatesRequest{})
	if err != nil {
		return nil, err
	}
	br := resp.GetBitRates()
	if br == nil {
		return &BitRates{}, nil
	}
	return &BitRates{
		InputBitRate:   bitRateInfoFromFFProto(br.GetInputBitRate()),
		EncodedBitRate: bitRateInfoFromFFProto(br.GetEncodedBitRate()),
		OutputBitRate:  bitRateInfoFromFFProto(br.GetOutputBitRate()),
	}, nil
}

func bitRateInfoFromFFProto(p *ffgrpc.BitRateInfo) BitRateInfo {
	if p == nil {
		return BitRateInfo{}
	}
	return BitRateInfo{
		Video: p.GetVideo(),
		Audio: p.GetAudio(),
		Other: p.GetOther(),
	}
}

func (r *RemoteFFStream) GetLatencies(ctx context.Context) (*Latencies, error) {
	resp, err := r.client.GetLatencies(ctx, &ffgrpc.GetLatenciesRequest{})
	if err != nil {
		return nil, err
	}
	lat := resp.GetLatencies()
	if lat == nil {
		return &Latencies{}, nil
	}
	return &Latencies{
		Audio: trackLatenciesFromFFProto(lat.GetAudio()),
		Video: trackLatenciesFromFFProto(lat.GetVideo()),
	}, nil
}

func trackLatenciesFromFFProto(p *ffgrpc.TrackLatencies) TrackLatencies {
	if p == nil {
		return TrackLatencies{}
	}
	return TrackLatencies{
		PreTranscodingUs:    p.GetPreTranscodingU(),
		TranscodingUs:       p.GetTranscodingU(),
		TranscodedPreSendUs: p.GetTranscodedPreSendU(),
		SendingUs:           p.GetSendingU(),
	}
}

func (r *RemoteFFStream) GetInputQuality(ctx context.Context) (*QualityReport, error) {
	resp, err := r.client.GetInputQuality(ctx, &ffgrpc.GetInputQualityRequest{})
	if err != nil {
		return nil, err
	}
	return &QualityReport{
		Audio: streamQualityFromFFProto(resp.GetAudio()),
		Video: streamQualityFromFFProto(resp.GetVideo()),
	}, nil
}

func (r *RemoteFFStream) GetOutputQuality(ctx context.Context) (*QualityReport, error) {
	resp, err := r.client.GetOutputQuality(ctx, &ffgrpc.GetOutputQualityRequest{})
	if err != nil {
		return nil, err
	}
	return &QualityReport{
		Audio: streamQualityFromFFProto(resp.GetAudio()),
		Video: streamQualityFromFFProto(resp.GetVideo()),
	}, nil
}

func streamQualityFromFFProto(p *ffgrpc.StreamQuality) StreamQuality {
	if p == nil {
		return StreamQuality{}
	}
	return StreamQuality{
		Continuity: p.GetContinuity(),
		FrameRate:  p.GetFrameRate(),
		Overlap:    p.GetOverlap(),
		InvalidDTS: p.GetInvalidDts(),
	}
}

func (r *RemoteFFStream) GetFPSFraction(ctx context.Context) (uint32, uint32, error) {
	resp, err := r.client.GetFPSFraction(ctx, &ffgrpc.GetFPSFractionRequest{})
	if err != nil {
		return 0, 0, err
	}
	return resp.GetNum(), resp.GetDen(), nil
}

func (r *RemoteFFStream) SetFPSFraction(ctx context.Context, num, den uint32) error {
	_, err := r.client.SetFPSFraction(ctx, &ffgrpc.SetFPSFractionRequest{
		Num: num,
		Den: den,
	})
	return err
}

func (r *RemoteFFStream) GetInputsInfo(ctx context.Context) ([]InputInfo, error) {
	resp, err := r.client.GetInputsInfo(ctx, &ffgrpc.GetInputsInfoRequest{})
	if err != nil {
		return nil, err
	}
	var result []InputInfo
	for _, i := range resp.GetInputs() {
		result = append(result, InputInfo{
			ID:         i.GetId(),
			Priority:   i.GetPriority(),
			Num:        i.GetNum(),
			URL:        i.GetUrl(),
			IsActive:   i.GetIsActive(),
			Suppressed: i.GetSuppressed(),
		})
	}
	return result, nil
}

func (r *RemoteFFStream) SetAutoBitRateVideoConfig(ctx context.Context, cfg AutoBitRateVideoConfig) error {
	return fmt.Errorf("SetAutoBitRateVideoConfig is not supported for remote ffstream")
}

func (r *RemoteFFStream) GetAutoBitRateVideoConfig(ctx context.Context) (*AutoBitRateVideoConfig, error) {
	return nil, fmt.Errorf("GetAutoBitRateVideoConfig is not supported for remote ffstream")
}

func (r *RemoteFFStream) InjectSubtitles(ctx context.Context, data []byte, dur time.Duration) error {
	_, err := r.client.InjectSubtitles(ctx, &ffgrpc.InjectSubtitlesRequest{
		Data:       data,
		DurationNs: uint64(dur.Nanoseconds()),
	})
	return err
}

func (r *RemoteFFStream) InjectData(ctx context.Context, data []byte, dur time.Duration) error {
	_, err := r.client.InjectData(ctx, &ffgrpc.InjectDataRequest{
		Data:       data,
		DurationNs: uint64(dur.Nanoseconds()),
	})
	return err
}

func (r *RemoteFFStream) GetOutputSRTStats(ctx context.Context, outputID int32) (*SRTStats, error) {
	resp, err := r.client.GetOutputSRTStats(ctx, &ffgrpc.GetOutputSRTStatsRequest{
		OutputId: outputID,
	})
	if err != nil {
		return nil, err
	}
	return &SRTStats{
		PktSent:     resp.GetPktSentTotal(),
		PktRecv:     resp.GetPktRecvTotal(),
		PktSendLoss: resp.GetPktSndLossTotal(),
		PktRecvLoss: resp.GetPktRcvLossTotal(),
		PktRetrans:  resp.GetPktRetransTotal(),
		PktSendDrop: resp.GetPktSndDropTotal(),
		PktRecvDrop: resp.GetPktRcvDropTotal(),
		BytesSent:   int64(resp.GetByteSentTotal()),
		BytesRecv:   int64(resp.GetByteRecvTotal()),
	}, nil
}

func (r *RemoteFFStream) Monitor(ctx context.Context, req MonitorRequest) (<-chan MonitorEvent, error) {
	return nil, fmt.Errorf("Monitor is not supported for remote ffstream")
}

func (r *RemoteFFStream) SetLoggingLevel(ctx context.Context, level int) error {
	_, err := r.client.SetLoggingLevel(ctx, &ffgrpc.SetLoggingLevelRequest{
		Level: ffgrpc.LoggingLevel(level),
	})
	return err
}

func (r *RemoteFFStream) GetPipelines(ctx context.Context) ([]Pipeline, error) {
	resp, err := r.client.GetPipelines(ctx, &ffgrpc.GetPipelinesRequest{})
	if err != nil {
		return nil, err
	}
	var result []Pipeline
	for _, n := range resp.GetNodes() {
		result = append(result, Pipeline{
			ID:          strconv.FormatUint(n.GetId(), 10),
			Description: n.GetDescription(),
		})
	}
	return result, nil
}

func (r *RemoteFFStream) GetVideoAutoBitRateCalculator(ctx context.Context) ([]byte, error) {
	return nil, fmt.Errorf("GetVideoAutoBitRateCalculator is not supported for remote ffstream")
}

func (r *RemoteFFStream) SetVideoAutoBitRateCalculator(ctx context.Context, config []byte) error {
	return fmt.Errorf("SetVideoAutoBitRateCalculator is not supported for remote ffstream")
}

func (r *RemoteFFStream) GetSRTFlagInt(ctx context.Context, flag SRTFlagInt) (int64, error) {
	resp, err := r.client.GetSRTFlagInt(ctx, &ffgrpc.GetSRTFlagIntRequest{
		Flag: ffgrpc.SRTFlagInt(flag),
	})
	if err != nil {
		return 0, err
	}
	return resp.GetValue(), nil
}

func (r *RemoteFFStream) SetSRTFlagInt(ctx context.Context, flag SRTFlagInt, value int64) error {
	_, err := r.client.SetSRTFlagInt(ctx, &ffgrpc.SetSRTFlagIntRequest{
		Flag:  ffgrpc.SRTFlagInt(flag),
		Value: value,
	})
	return err
}

func (r *RemoteFFStream) SetInputCustomOption(ctx context.Context, inputID string, key string, value string) error {
	return fmt.Errorf("SetInputCustomOption with string inputID is not supported for remote ffstream")
}

func (r *RemoteFFStream) SetStopInput(ctx context.Context, inputID string) error {
	return fmt.Errorf("SetStopInput with string inputID is not supported for remote ffstream")
}

func (r *RemoteFFStream) End(ctx context.Context) error {
	_, err := r.client.End(ctx, &ffgrpc.EndRequest{})
	return err
}

func (r *RemoteFFStream) WaitChan(ctx context.Context) (<-chan struct{}, error) {
	stream, err := r.client.WaitChan(ctx, &ffgrpc.WaitRequest{})
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

func (r *RemoteFFStream) InjectDiagnostics(ctx context.Context, diagnostics *Diagnostics, durationNs uint64) error {
	return fmt.Errorf("InjectDiagnostics is not supported for remote ffstream")
}

func (r *RemoteFFStream) FFSetLoggingLevel(ctx context.Context, level int) error {
	return r.SetLoggingLevel(ctx, level)
}

func nodeCountersFromAVProto(nc *avpipeline.NodeCounters) NodeCounters {
	countTotal := func(section *avpipeline.NodeCountersSection) (packets, frames uint64) {
		if section == nil {
			return 0, 0
		}
		if p := section.GetPackets(); p != nil {
			for _, item := range []*avpipeline.NodeCountersItem{p.GetUnknown(), p.GetOther(), p.GetVideo(), p.GetAudio()} {
				if item != nil {
					packets += item.GetCount()
				}
			}
		}
		if f := section.GetFrames(); f != nil {
			for _, item := range []*avpipeline.NodeCountersItem{f.GetUnknown(), f.GetOther(), f.GetVideo(), f.GetAudio()} {
				if item != nil {
					frames += item.GetCount()
				}
			}
		}
		return
	}
	rp, rf := countTotal(nc.GetReceived())
	pp, pf := countTotal(nc.GetProcessed())
	mp, mf := countTotal(nc.GetMissed())
	gp, gf := countTotal(nc.GetGenerated())
	sp, sf := countTotal(nc.GetSent())
	return NodeCounters{
		ReceivedPackets:  rp,
		ReceivedFrames:   rf,
		ProcessedPackets: pp,
		ProcessedFrames:  pf,
		MissedPackets:    mp,
		MissedFrames:     mf,
		GeneratedPackets: gp,
		GeneratedFrames:  gf,
		SentPackets:      sp,
		SentFrames:       sf,
	}
}
