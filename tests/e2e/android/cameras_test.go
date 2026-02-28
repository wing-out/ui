//go:build android_e2e

package android

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestCameras_EmptyState(t *testing.T) {
	env := sharedEnv

	// Override mock to return empty sources
	origFunc := env.mockSD.ListStreamSourcesFunc
	env.mockSD.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")

	node, err := env.adb.WaitForElement("camerasPage", elementTimeout)
	require.NoError(t, err)
	require.NotNil(t, node)
	Sleep(1 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	emptyNodes := hierarchy.FindContainingText("No cameras")
	require.NotEmpty(t, emptyNodes, "empty state 'No cameras configured' should be visible")

	addBtn := hierarchy.FindContainingText("Add Source")
	require.NotEmpty(t, addBtn, "Add Source button should be visible")
	screenshot(t, env, "cameras_empty")

	// Restore
	env.mockSD.ListStreamSourcesFunc = origFunc
}

func TestCameras_PageTitle(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")

	_, err := env.adb.WaitForTextContaining("Cameras", 5*time.Second)
	require.NoError(t, err, "top bar should show 'Cameras' title")
	screenshot(t, env, "cameras_title")
}

func TestCameras_SourceListWithData(t *testing.T) {
	env := sharedEnv

	// Ensure ListStreamSources returns cam0 (active) and cam1 (inactive)
	env.mockSD.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{
			{ID: "cam0", URL: "rtmp://localhost/cam0", IsActive: true},
			{ID: "cam1", URL: "rtmp://localhost/cam1", IsActive: false},
		}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	require.NotEmpty(t, hierarchy.FindContainingText("cam0"), "cam0 source should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("cam1"), "cam1 source should be visible")

	// Check active/inactive status badges
	require.NotEmpty(t, hierarchy.FindContainingText("Active"), "Active badge should be visible for cam0")
	require.NotEmpty(t, hierarchy.FindContainingText("Inactive"), "Inactive badge should be visible for cam1")

	screenshot(t, env, "cameras_source_list")
}

func TestCameras_ServersList(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	// Stream Servers section heading
	require.NotEmpty(t, hierarchy.FindContainingText("Stream Servers"), "Stream Servers heading should be visible")

	// Mock returns rtmp_main and srt_backup servers
	require.NotEmpty(t, hierarchy.FindContainingText("rtmp_main"), "rtmp_main server should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText("srt_backup"), "srt_backup server should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText(":1935"), "rtmp listen address should be visible")
	require.NotEmpty(t, hierarchy.FindContainingText(":9000"), "srt listen address should be visible")

	screenshot(t, env, "cameras_servers")
}

func TestCameras_AddSourceForm(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(1 * time.Second)

	// Tap Add Source button to open the form
	addBtn, err := env.adb.WaitForElement("addSourceButton", elementTimeout)
	require.NoError(t, err, "Add Source button should exist")
	require.NoError(t, env.adb.TapNode(addBtn))
	Sleep(500 * time.Millisecond)

	// Verify form fields appear
	_, err = env.adb.WaitForElement("sourceIdField", 5*time.Second)
	require.NoError(t, err, "Source ID field should appear after tapping Add Source")

	_, err = env.adb.WaitForElement("sourceUrlField", 5*time.Second)
	require.NoError(t, err, "Source URL field should appear after tapping Add Source")

	_, err = env.adb.WaitForElement("confirmAddSourceButton", 5*time.Second)
	require.NoError(t, err, "Confirm Add button should appear")

	screenshot(t, env, "cameras_add_source_form")
}

func TestCameras_RemoveSourceButton(t *testing.T) {
	env := sharedEnv

	// Ensure sources are present
	env.mockSD.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{
			{ID: "cam0", URL: "rtmp://localhost/cam0", IsActive: true},
		}, nil
	}

	resetApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	hierarchy, err := env.adb.DumpUI()
	require.NoError(t, err)

	removeButtons := hierarchy.FindAllByContentDesc("removeSourceBtn")
	require.NotEmpty(t, removeButtons, "Remove button should exist for each source")

	screenshot(t, env, "cameras_remove_button")
}

func TestCameras_BackendCalled(t *testing.T) {
	env := sharedEnv
	resetApp(t, env)
	completeSetup(t, env)

	env.mockSD.ResetCallCounts()
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ListStreamSources"), 1, "ListStreamSources should have been called")
	require.GreaterOrEqual(t, env.mockSD.CallCount("ListStreamServers"), 1, "ListStreamServers should have been called")
}
