import QtQuick
import QtQuick.Controls
import QtMultimedia

Rectangle {
    id: videoPlayerRTMP
    color: '#000000'

    property string streamName: ""

    property alias audioMuted: audioOutput.muted
    property alias source: mediaPlayer.source
    property alias mediaPlayer: mediaPlayer
    property alias videoOutput: videoOutput
    property alias audioOutput: audioOutput
    property alias muteToggleButton: muteToggleButton
    property alias lastProgressAt: mediaPlayer.lastProgressAt
    property real videoFrameRate: -1

    function stop() {
        mediaPlayer.stop();
    }
    function play() {
        mediaPlayer.play();
    }
    function pause() {
        mediaPlayer.pause();
    }
    function setSource(newSource) {
        mediaPlayer.setSource(newSource);
    }

    MediaPlayer {
        id: mediaPlayer
        source: videoPlayerRTMP.source
        autoPlay: true
        playbackRate: audioOutput.muted ? 10.0 : 1.0
        playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
        playbackOptions.probeSize: -1
        // networkTimeoutMs must be 0: Qt passes it as "timeout" to FFmpeg,
        // which collides with RTMP's "timeout" option (= listen_timeout).
        // Any positive value triggers RTMP server/listen mode, causing
        // bind(remote_addr) → EADDRNOTAVAIL on Android.
        playbackOptions.networkTimeoutMs: 0

        Component.onCompleted: {
            var src = String(mediaPlayer.source || "").trim();
            if (src.length > 0) {
                mediaPlayer.setSource(src);
                mediaPlayer.play();
                mediaPlayer.statusLogRemaining = 12;
            }
            videoPlayerRTMP.updateVideoFrameRate();
            console.log("MediaPlayer source: ", mediaPlayer.source);
            console.log("MediaPlayer init state:", mediaPlayer.playbackState, "status:", mediaPlayer.mediaStatus, "playing:", mediaPlayer.playing);
        }

        property var lastProgressAt: Date.now()
        property var lastRestartAt: 0
        property var started: false
        // Guard flag: true while onSourceChanged is executing, prevents
        // the retry timer from interfering with the source transition.
        property bool sourceTransitioning: false
        // Exponential backoff: current retry delay in ms (3000 → 5000 max).
        // Must be ≥ 3000 to allow RTMP handshake + stream probe to complete.
        property int retryBackoffMs: 3000
        property bool loggedFirstPosition: false
        property int statusLogRemaining: 0

        videoOutput: videoOutput
        audioOutput: audioOutput

        onSourceChanged: function (newSource) {
            console.log("onSourceChanged: ", newSource);
            mediaPlayer.sourceTransitioning = true;
            mediaPlayer.stop();
            mediaPlayer.setSource(newSource);
            mediaPlayer.play();
            mediaPlayer.retryBackoffMs = 3000;
            mediaPlayer.sourceTransitioning = false;
            mediaPlayer.statusLogRemaining = 12;
            videoPlayerRTMP.videoFrameRate = -1;
        }
        onErrorOccurred: function (code, msg) {
            console.log("onErrorOccurred:", code, " ", msg);
        }
        onMediaStatusChanged: {
            console.log("onMediaStatusChanged: ", mediaPlayer.mediaStatus);
        }
        onPlaybackStateChanged: {
            console.log("onPlaybackStateChanged: ", mediaPlayer.playbackState);
        }
        onPlayingChanged: function () {
            console.log("onPlayingChanged: ", mediaPlayer.playing);
            if (!mediaPlayer.playing) {
                mediaPlayer.started = false;
            }
        }
        onPositionChanged: function () {
            //console.log("onPositionChanged: ", mediaPlayer.position);
            mediaPlayer.lastProgressAt = Date.now();
            mediaPlayer.started = true;
            // Reset backoff on successful playback progress.
            mediaPlayer.retryBackoffMs = 3000;
            if (!mediaPlayer.loggedFirstPosition && mediaPlayer.position > 0) {
                mediaPlayer.loggedFirstPosition = true;
                console.log("MediaPlayer first position:", mediaPlayer.position, "source:", mediaPlayer.source);
            }
        }
        onDurationChanged: function () {
            console.log("onDurationChanged: ", mediaPlayer.duration);
        }
        onBufferProgressChanged: function () {
            console.log("onBufferProgressChanged: ", mediaPlayer.bufferProgress);
        }
        onPlaybackRateChanged: function () {
            console.log("onPlaybackRateChanged: ", mediaPlayer.playbackRate);
        }
        onMetaDataChanged: function () {
            videoPlayerRTMP.updateVideoFrameRate();
        }
    }

    function updateVideoFrameRate() {
        var meta = mediaPlayer.metaData;
        if (!meta) {
            videoFrameRate = -1;
            return;
        }
        var fps = Number(meta.videoFrameRate);
        if (!isFinite(fps) || fps <= 0) {
            videoFrameRate = -1;
            return;
        }
        videoFrameRate = fps;
    }

    Timer {
        id: statusLogTimer
        interval: 500
        repeat: true
        running: mediaPlayer.statusLogRemaining > 0
        onTriggered: {
            console.log(
                "MediaPlayer status tick:",
                "state", mediaPlayer.playbackState,
                "status", mediaPlayer.mediaStatus,
                "playing", mediaPlayer.playing,
                "error", mediaPlayer.error,
                "errorString", mediaPlayer.errorString,
                "source", mediaPlayer.source
            );
            mediaPlayer.statusLogRemaining--;
        }
    }

    Timer {
        id: steadyStatusLogTimer
        interval: 1500
        repeat: true
        running: true
        onTriggered: {
            console.log(
                "MediaPlayer steady tick:",
                "state", mediaPlayer.playbackState,
                "status", mediaPlayer.mediaStatus,
                "playing", mediaPlayer.playing,
                "error", mediaPlayer.error,
                "errorString", mediaPlayer.errorString,
                "source", mediaPlayer.source
            );
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
    }
    AudioOutput {
        id: audioOutput
        muted: true
    }

    ToolButton {
        id: muteToggleButton
        anchors.margins: 12
        anchors.top: parent.top
        anchors.left: parent.left
        font.pixelSize: 40
        checkable: true
        checked: audioOutput.muted
        property real defaultOpacity: 0.5
        opacity: hovered ? 1.0 : defaultOpacity
        onToggled: audioOutput.muted = checked
        text: checked ? "🔇" : "🔊"
        ToolTip.visible: hovered
        ToolTip.text: checked ? "Unmute" : "Mute"
    }

    Timer {
        id: retryTimer
        interval: 100
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now();
            // Skip if a source transition is in progress.
            if (mediaPlayer.sourceTransitioning) {
                return;
            }
            // Skip if currently making progress (playing and receiving data).
            if ((mediaPlayer.playbackState === MediaPlayer.PlayingState || mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia) && (now - mediaPlayer.lastProgressAt < 1000)) {
                return;
            }
            // Exponential backoff: wait retryBackoffMs before retrying
            // after a failed attempt (replaces fixed 10-second dead zone).
            if (now - mediaPlayer.lastRestartAt < mediaPlayer.retryBackoffMs) {
                return;
            }
            var source = mediaPlayer.source;
            // Skip if source is empty — retrying with no URL creates a
            // permanent empty-source loop.
            if (!source || source === "") {
                return;
            }
            console.log("RetryTimer triggered (backoff=", mediaPlayer.retryBackoffMs, "ms): playbackState=", mediaPlayer.playbackState, " source=", source);
            mediaPlayer.lastProgressAt = now;
            mediaPlayer.lastRestartAt = now;
            // Increase backoff for next attempt: 500 → 1000 → 2000 → 5000 max.
            mediaPlayer.retryBackoffMs = Math.min(mediaPlayer.retryBackoffMs * 2, 5000);
            mediaPlayer.stop();
            mediaPlayer.setSource("");
            mediaPlayer.setSource(source);
            mediaPlayer.play();
        }
    }
}
