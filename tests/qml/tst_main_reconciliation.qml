import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

TestCase {
    id: tc
    name: "MainReconciliation"
    when: windowShown
    width: 540
    height: 960

    readonly property string canonicalPublisherUrl:
        "rtmp://127.0.0.1:1946/live/builtincamera-${v:0:codec}${a:0:codec}-${v:0:height}${a:0:rate}/"

    Component {
        id: appSettingsStub
        QtObject {
            property string dxProducerHost: ""
            property string previewRTMPUrl: ""
            property string ffstreamHost: ""
        }
    }

    Component {
        id: platformStub
        QtObject {
            function refreshWiFiState() {}
        }
    }

    Component {
        id: mainComponent
        Main {
            platformInstance: platformStub.createObject(tc)
            appSettings: appSettingsStub.createObject(tc)
        }
    }

    Component {
        id: mediamtxNoBuiltinInputsClient
        QtObject {
            property int getInputsInfoCalls: 0
            property int switchOutputCalls: 0
            property int setOutputUrlCalls: 0
            property var switchOutputCodecs: []
            function isChannelReady() { return true }
            function processGRPCError(_) {}
            function getInputsInfo(onSuccess, _onError, _options) {
                getInputsInfoCalls += 1
                onSuccess({ "inputsData": [] })
            }
            function setOutputUrl(_url, onSuccess, _onError, _options) {
                setOutputUrlCalls += 1
                onSuccess({})
            }
            function switchOutput(_videoCodec, _width, _height, _bitrate,
                                  _audioCodec, _sampleRate, _audioBitrate,
                                  _maxBitrate, onSuccess, _onError, _options) {
                switchOutputCalls += 1
                switchOutputCodecs.push(_videoCodec)
                onSuccess({})
            }
        }
    }

    Component {
        id: mediamtxWithBuiltinInputsClient
        QtObject {
            property int getInputsInfoCalls: 0
            property int switchOutputCalls: 0
            property int setOutputUrlCalls: 0
            property var switchOutputCodecs: []
            function isChannelReady() { return true }
            function processGRPCError(_) {}
            function getInputsInfo(onSuccess, _onError, _options) {
                getInputsInfoCalls += 1
                onSuccess({
                    "inputsData": [
                        {
                            "priority": 0,
                            "inputConfig": {
                                "customOptionsData": [
                                    { "key": "f", "value": "android_camera" }
                                ]
                            }
                        },
                        {
                            "priority": 0,
                            "inputConfig": {
                                "customOptionsData": [
                                    { "key": "f", "value": "android_microphone" }
                                ]
                            }
                        }
                    ]
                })
            }
            function setOutputUrl(_url, onSuccess, _onError, _options) {
                setOutputUrlCalls += 1
                onSuccess({})
            }
            function switchOutput(_videoCodec, _width, _height, _bitrate,
                                  _audioCodec, _sampleRate, _audioBitrate,
                                  _maxBitrate, onSuccess, _onError, _options) {
                switchOutputCalls += 1
                switchOutputCodecs.push(_videoCodec)
                onSuccess({})
            }
        }
    }

    Component {
        id: cameraWithBuiltinInputsClient
        QtObject {
            property int getInputsInfoCalls: 0
            property int switchOutputCalls: 0
            property int setOutputUrlCalls: 0
            property var switchOutputCodecs: []
            function isChannelReady() { return true }
            function processGRPCError(_) {}
            function getInputsInfo(onSuccess, _onError, _options) {
                getInputsInfoCalls += 1
                onSuccess({
                    "inputsData": [
                        {
                            "priority": 0,
                            "inputConfig": {
                                "customOptionsData": [
                                    { "key": "f", "value": "android_camera" }
                                ]
                            }
                        },
                        {
                            "priority": 0,
                            "inputConfig": {
                                "customOptionsData": [
                                    { "key": "f", "value": "android_microphone" }
                                ]
                            }
                        }
                    ]
                })
            }
            function setOutputUrl(url, onSuccess, _onError, _options) {
                setOutputUrlCalls += 1
                compare(url, tc.canonicalPublisherUrl,
                        "camera reconcile must publish to the built-in-camera publisher URL")
                onSuccess({})
            }
            function switchOutput(_videoCodec, _width, _height, _bitrate,
                                  _audioCodec, _sampleRate, _audioBitrate,
                                  _maxBitrate, onSuccess, _onError, _options) {
                switchOutputCalls += 1
                switchOutputCodecs.push(_videoCodec)
                onSuccess({})
            }
        }
    }

    function findButtonByText(root, text) {
        if (!root) {
            return null
        }
        if (root.text === text && root.enabled !== undefined) {
            return root
        }
        var children = root.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = findButtonByText(children[i], text)
            if (found) {
                return found
            }
        }
        return null
    }

    function createMainOnCamerasPage() {
        var main = createTemporaryObject(mainComponent, tc)
        verify(main !== null, "Main must instantiate")
        var stack = findChild(main, "stack")
        verify(stack !== null, "Main stack must be findable")
        stack.currentIndex = 1
        wait(50)
        return main
    }

    function test_01_camera_reconcile_keeps_deactivate_enabled_after_mediamtx_no_builtin_inputs() {
        var main = createMainOnCamerasPage()
        main.streamingSettings.outputUrl = "rtmp://127.0.0.1:1945/live/builtincamera-merged"
        main.streamingSettings.videoCodec = "h264_mediacodec"

        var cameraClient = createTemporaryObject(cameraWithBuiltinInputsClient, tc)
        main.reconcileWithFFStreamCamera(cameraClient)
        compare(cameraClient.getInputsInfoCalls, 1,
                "camera reconcile must query the camera daemon")
        compare(cameraClient.setOutputUrlCalls, 1,
                "camera reconcile must auto-apply the publisher URL")
        compare(cameraClient.switchOutputCalls, 1,
                "camera reconcile must auto-apply SwitchOutput")
        compare(main.streamingSettings.videoCodec, "av1_mediacodec",
                "camera reconcile must reset stale persisted codec to AV1")
        compare(cameraClient.switchOutputCodecs[0], "av1_mediacodec",
                "camera reconcile must send AV1 to ffstream-camera")
        verify(cameraClient.switchOutputCodecs[0] !== "h264_mediacodec",
               "camera reconcile must not send stale persisted H.264")
        verify(main.streamingSettings.active,
               "camera daemon built-in inputs must mark the shared camera UI active")

        var deactivateButton = findButtonByText(main, "Deactivate")
        verify(deactivateButton !== null, "Deactivate button must be present")
        verify(deactivateButton.enabled,
               "Deactivate must be enabled while ffstream-camera is active")

        var mediamtxClient = createTemporaryObject(mediamtxNoBuiltinInputsClient, tc)
        main.reconcileWithFFStream(mediamtxClient)
        compare(mediamtxClient.getInputsInfoCalls, 1,
                "mediamtx reconcile still queries its own daemon")
        compare(mediamtxClient.setOutputUrlCalls, 0,
                "no mediamtx built-in inputs means no output auto-apply")
        compare(mediamtxClient.switchOutputCalls, 0,
                "no mediamtx built-in inputs means no SwitchOutput auto-apply")

        verify(main.streamingSettings.active,
               "mediamtx-side no-built-in-inputs reconcile must not clobber camera active state")
        verify(deactivateButton.enabled,
               "Deactivate must remain enabled from ffstreamCameraClient ownership")
    }

    function test_02_mediamtx_reconcile_sends_required_av1_not_persisted_h264() {
        var main = createMainOnCamerasPage()
        main.streamingSettings.outputUrl = "rtmp://127.0.0.1:1945/live/example-source-merged"
        main.streamingSettings.videoCodec = "h264_mediacodec"

        var mediamtxClient = createTemporaryObject(mediamtxWithBuiltinInputsClient, tc)
        main.reconcileWithFFStream(mediamtxClient)

        compare(mediamtxClient.getInputsInfoCalls, 1,
                "mediamtx reconcile must query the legacy daemon")
        compare(mediamtxClient.switchOutputCalls, 1,
                "mediamtx reconcile must auto-apply SwitchOutput when legacy built-in inputs exist")
        compare(main.streamingSettings.videoCodec, "av1_mediacodec",
                "mediamtx reconcile must normalize stale persisted codec to required AV1")
        compare(mediamtxClient.switchOutputCodecs[0], "av1_mediacodec",
                "mediamtx reconcile must send AV1 to the client")
        verify(mediamtxClient.switchOutputCodecs[0] !== "h264_mediacodec",
               "mediamtx reconcile must not send stale persisted H.264")
    }
}
