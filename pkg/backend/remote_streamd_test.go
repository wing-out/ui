package backend

import (
	"testing"

	chatgrpc "github.com/xaionaro-go/chatwebhook/pkg/grpc/protobuf/go/chatwebhook_grpc"
	sdgrpc "github.com/xaionaro-go/streamctl/pkg/streamd/grpc/go/streamd_grpc"
	"github.com/stretchr/testify/require"
)

func TestConvertStreamDChatMessage_Timestamp(t *testing.T) {
	// 2026-02-28 09:00:00 UTC in nanoseconds
	const tsNano uint64 = 1772010000_000_000_000

	msg := &sdgrpc.ChatMessage{
		PlatID: "twitch",
		Content: &chatgrpc.Event{
			CreatedAtUNIXNano: tsNano,
			User: &chatgrpc.User{
				Id:   "u123",
				Name: "testuser",
			},
			Message: &chatgrpc.Message{
				Content: "hello world",
			},
		},
	}

	cm := convertStreamDChatMessage(msg)

	require.Equal(t, "twitch", cm.Platform)
	require.Equal(t, "testuser", cm.UserName)
	require.Equal(t, "hello world", cm.Message)
	require.Equal(t, int64(1772010000), cm.Timestamp,
		"timestamp must be extracted from content.CreatedAtUNIXNano (nanoseconds → seconds)")
}

func TestConvertStreamDChatMessage_NoContent(t *testing.T) {
	msg := &sdgrpc.ChatMessage{
		PlatID: "youtube",
	}

	cm := convertStreamDChatMessage(msg)

	require.Equal(t, "youtube", cm.Platform)
	require.Equal(t, int64(0), cm.Timestamp,
		"timestamp should be 0 when content is nil")
}

func TestConvertStreamDChatMessage_ZeroTimestamp(t *testing.T) {
	msg := &sdgrpc.ChatMessage{
		PlatID: "kick",
		Content: &chatgrpc.Event{
			CreatedAtUNIXNano: 0,
			Message: &chatgrpc.Message{
				Content: "test",
			},
		},
	}

	cm := convertStreamDChatMessage(msg)

	require.Equal(t, int64(0), cm.Timestamp,
		"timestamp should remain 0 when createdAtUNIXNano is 0")
}
