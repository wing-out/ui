//go:build desktop_e2e

package desktop

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/xaionaro-go/wingout2/pkg/backend"
)

func TestDesktop_CamerasPageLoads(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")

	node, err := env.atspi.WaitForElement("camerasPage", elementTimeout)
	require.NoError(t, err, "cameras page should be visible")
	require.NotNil(t, node)
	screenshot(t, env, "cameras_page")
}

func TestDesktop_SourcesList(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// With empty sources from mock, we should see the empty state
	emptyNodes := tree.FindContainingText("No cameras")
	require.NotEmpty(t, emptyNodes, "empty state 'No cameras' should be visible")

	addBtn := tree.FindByName("addSourceButton")
	require.NotNil(t, addBtn, "Add Source button should be visible")
	screenshot(t, env, "cameras_empty_sources")
}

func TestDesktop_ServersList(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Mock returns 2 stream servers
	rtmpNodes := tree.FindContainingText("rtmp_main")
	require.NotEmpty(t, rtmpNodes, "rtmp_main server should be visible")

	srtNodes := tree.FindContainingText("srt_backup")
	require.NotEmpty(t, srtNodes, "srt_backup server should be visible")
	screenshot(t, env, "cameras_servers")
}

func TestDesktop_CamerasPageTitle(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")

	err := env.atspi.WaitForText("Cameras", 5*time.Second)
	require.NoError(t, err, "top bar should show 'Cameras' title")
	screenshot(t, env, "cameras_title")
}

func TestDesktop_SourcesListWithData(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	// Mock returns cam0 and cam1 sources
	require.NotEmpty(t, tree.FindContainingText("cam0"), "cam0 source should be visible")
	require.NotEmpty(t, tree.FindContainingText("cam1"), "cam1 source should be visible")
	require.NotEmpty(t, tree.FindContainingText("rtmp://localhost/cam0"), "cam0 URL should be visible")
	screenshot(t, env, "cameras_sources_data")
}

func TestDesktop_CamerasAddSourceForm(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(1 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	addBtn := tree.FindByName("addSourceButton")
	require.NotNil(t, addBtn, "Add Source button should exist")

	// Tap to open the add source form
	require.NoError(t, env.atspi.ActivateByName("addSourceButton"))
	Sleep(1 * time.Second)

	tree, err = env.atspi.DumpTree()
	require.NoError(t, err)

	idField := tree.FindByName("sourceIdField")
	require.NotNil(t, idField, "Source ID field should exist in add form")

	urlField := tree.FindByName("sourceUrlField")
	require.NotNil(t, urlField, "Source URL field should exist in add form")

	confirmBtn := tree.FindByName("confirmAddSourceButton")
	require.NotNil(t, confirmBtn, "Confirm Add Source button should exist")
	screenshot(t, env, "cameras_add_form")
}

func TestDesktop_CamerasAddSourceCallsBackend(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(1 * time.Second)

	// Tap Add Source button
	require.NoError(t, env.atspi.ActivateByName("addSourceButton"))
	Sleep(1 * time.Second)

	// Fill URL field
	require.NoError(t, env.atspi.ActivateByName("sourceUrlField"))
	Sleep(300 * time.Millisecond)
	require.NoError(t, env.atspi.TypeText("rtmp://localhost/newcam"))
	Sleep(300 * time.Millisecond)

	env.mockSD.ResetCallCounts()

	// Tap confirm
	require.NoError(t, env.atspi.ActivateByName("confirmAddSourceButton"))
	Sleep(1 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("AddStreamSource"), 1,
		"AddStreamSource should have been called after confirming add")
	screenshot(t, env, "cameras_add_source_backend")
}

func TestDesktop_CamerasRemoveSourceButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	removeBtn := tree.FindByName("removeSourceBtn")
	require.NotNil(t, removeBtn, "Remove Source button should exist for sources")
	screenshot(t, env, "cameras_remove_button")
}

func TestDesktop_CamerasStopServerButton(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	stopBtn := tree.FindByName("stopServerBtn")
	require.NotNil(t, stopBtn, "Stop Server button should exist")
	screenshot(t, env, "cameras_stop_server")
}

func TestDesktop_CamerasEmptySourcesState(t *testing.T) {
	env := sharedEnv

	origFunc := env.mockSD.ListStreamSourcesFunc
	env.mockSD.ListStreamSourcesFunc = func(ctx context.Context) ([]backend.StreamSource, error) {
		return []backend.StreamSource{}, nil
	}

	freshApp(t, env)
	completeSetup(t, env)
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	tree, err := env.atspi.DumpTree()
	require.NoError(t, err)

	emptyNodes := tree.FindContainingText("No cameras")
	require.NotEmpty(t, emptyNodes, "empty state 'No cameras' should be visible with empty sources")
	screenshot(t, env, "cameras_empty_sources_state")

	// Restore
	env.mockSD.ListStreamSourcesFunc = origFunc
}

func TestDesktop_CamerasBackendCalled(t *testing.T) {
	env := sharedEnv
	freshApp(t, env)
	completeSetup(t, env)

	env.mockSD.ResetCallCounts()
	navigateToPage(t, env, "Cameras")
	Sleep(2 * time.Second)

	require.GreaterOrEqual(t, env.mockSD.CallCount("ListStreamSources"), 1,
		"ListStreamSources should have been called by the Cameras page")
	require.GreaterOrEqual(t, env.mockSD.CallCount("ListStreamServers"), 1,
		"ListStreamServers should have been called by the Cameras page")
}
