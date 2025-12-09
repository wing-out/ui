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

    function stop() { mediaPlayer.stop() }
    function play() { mediaPlayer.play() }
    function pause() { mediaPlayer.pause() }
    function setSource(newSource) { mediaPlayer.setSource(newSource) }

    MediaPlayer {
        id: mediaPlayer
        source: videoPlayerRTMP.source
        autoPlay: true
        playbackRate: audioOutput.muted ? 10.0 : 1.0
        playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
        playbackOptions.probeSize: 2048
        playbackOptions.networkTimeoutMs: 0

        videoOutput: videoOutput
        audioOutput: AudioOutput {
            id: audioOutput
            muted: true
        }

        onSourceChanged: function (newSource) {
            console.log("onSourceChanged: ", newSource);
            mediaPlayer.stop();
            mediaPlayer.setSource(newSource);
            mediaPlayer.play();
        }
        onErrorOccurred: function (code, msg) {
            //console.log("onErrorOccurred:", code, " ", msg);
            if (!retryTimer.running)
                retryTimer.start()
        }
        onPlaybackStateChanged: {
            console.log("onPlaybackStateChanged: ", mediaPlayer.playbackState);
            if (playbackState === MediaPlayer.PlayingState && retryTimer.running)
                retryTimer.stop()
        }
        onPlayingChanged: function () {
            console.log("onPlayingChanged: ", mediaPlayer.playing);
        }
        Component.onCompleted: function () {
            console.log("MediaPlayer source: ", mediaPlayer.source);
        }
    }
    VideoOutput {
        id: videoOutput
        anchors.fill: parent

    }
    ToolButton {
        id: muteToggleButton
        anchors.margins: 12
        anchors.top: parent.top
        anchors.left: parent.left
        font.pixelSize: 60
        checkable: true
        checked: audioOutput.muted
        onToggled: audioOutput.muted = checked
        text: checked ? "🔇" : "🔊"
        ToolTip.visible: hovered
        ToolTip.text: checked ? "Unmute" : "Mute"
    }

    Timer {
        id: retryTimer
        interval: 100
        repeat: true
        running: false
        triggeredOnStart: true
        onTriggered: {
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState ||
                mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia) {
                return;
            }
            mediaPlayer.stop()
            var source = mediaPlayer.source
            mediaPlayer.setSource("")
            mediaPlayer.setSource(source)
            //console.log("Retrying stream: ", source);
            mediaPlayer.play()
        }
    }
}
