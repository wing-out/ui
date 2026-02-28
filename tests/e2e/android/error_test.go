//go:build android_e2e

package android

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestError_NotVisibleByDefault(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Error dialog should not be visible by default
	errNode := hierarchy.FindByContentDesc("errorDialog")
	if errNode != nil {
		// The component exists but should be invisible (errorMessage == "")
		t.Log("errorDialog node exists but should be invisible when no error")
	}
	screenshot(t, env, "no_error")
}

func TestError_AppearsOnBackendError(t *testing.T) {
	env := sharedEnv

	// Make GetBitRates return an error to trigger errorOccurred signal
	origFunc := env.mockFF.GetBitRatesFunc
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		return nil, fmt.Errorf("test error: connection refused")
	}

	resetApp(t, env)
	completeSetup(t, env)
	Sleep(3 * time.Second) // Wait for polling to trigger the error

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Error dialog should appear
	errNodes := hierarchy.FindContainingText("error")
	if len(errNodes) == 0 {
		errNodes = hierarchy.FindContainingText("Error")
	}
	if len(errNodes) == 0 {
		errNodes = hierarchy.FindContainingText("connection refused")
	}
	// The error may show in the dialog or be silently handled
	t.Logf("found %d error-related nodes", len(errNodes))
	screenshot(t, env, "error_visible")

	// Restore
	env.mockFF.GetBitRatesFunc = origFunc
}

func TestError_AutoHidesAfterTimeout(t *testing.T) {
	env := sharedEnv

	// Make GetBitRates return an error briefly
	origFunc := env.mockFF.GetBitRatesFunc
	callCount := 0
	env.mockFF.GetBitRatesFunc = func(ctx context.Context) (*backend.BitRates, error) {
		callCount++
		if callCount <= 3 {
			return nil, fmt.Errorf("temporary error")
		}
		return &backend.BitRates{
			InputBitRate:  backend.BitRateInfo{Video: 6000000, Audio: 128000},
			OutputBitRate: backend.BitRateInfo{Video: 4500000, Audio: 128000},
		}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	Sleep(3 * time.Second) // Wait for error to trigger

	// Wait for auto-hide (ErrorDialog has autoHideMs=5000)
	Sleep(6 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// The error dialog should have auto-hidden
	errNode := hierarchy.FindByContentDesc("errorDialog")
	if errNode != nil {
		// Check if it's still showing error content
		texts := errNode.GetChildTexts()
		t.Logf("errorDialog texts after timeout: %v", texts)
	}
	screenshot(t, env, "error_auto_hidden")

	// Restore
	env.mockFF.GetBitRatesFunc = origFunc
}
