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
        playbackOptions.networkTimeoutMs: 0

        property var lastProgressAt: Date.now()
        property var lastRestartAt: 0
        property var started: false

        videoOutput: videoOutput
        audioOutput: audioOutput

        onSourceChanged: function (newSource) {
            //console.log("onSourceChanged: ", newSource);
            mediaPlayer.stop();
            mediaPlayer.setSource(newSource);
            mediaPlayer.play();
        }
        onErrorOccurred: function (code, msg) {
        //console.log("onErrorOccurred:", code, " ", msg);
        }
        onMediaStatusChanged: {
            //console.log("onMediaStatusChanged: ", mediaPlayer.mediaStatus);
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
        //console.log("onMetaDataChanged: ", mediaPlayer.metaData);
        }
        Component.onCompleted: function () {
            console.log("MediaPlayer source: ", mediaPlayer.source);
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
            //console.log("RetryTimer check: playbackState=", mediaPlayer.playbackState, " mediaStatus=", mediaPlayer.mediaStatus, " lastProgressAt=", mediaPlayer.lastProgressAt, " now=", now);
            if ((mediaPlayer.playbackState === MediaPlayer.PlayingState || mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia) && (now - mediaPlayer.lastProgressAt < 1000)) {
                return;
            }
            if ((!mediaPlayer.started) && (now - mediaPlayer.lastRestartAt < 10000)) {
                return;
            }
            //console.log("RetryTimer triggered: playbackState=", mediaPlayer.playbackState, " mediaStatus=", mediaPlayer.mediaStatus, " lastProgressAt=", mediaPlayer.lastProgressAt, " now=", now);
            mediaPlayer.lastProgressAt = now;
            mediaPlayer.lastRestartAt = now;
            mediaPlayer.stop();
            var source = mediaPlayer.source;
            mediaPlayer.setSource("");
            mediaPlayer.setSource(source);
            //console.log("Retrying stream: ", source);
            mediaPlayer.play();
        }
    }
}
