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

    MediaPlayer {
        id: mediaPlayer
        source: videoPlayerRTMP.source
        autoPlay: true
        playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
        playbackOptions.probeSize: 2048
        playbackOptions.networkTimeoutMs: 0

        videoOutput: videoOutput
        audioOutput: AudioOutput {
            id: audioOutput
            muted: true
        }
        onErrorOccurred: (code, msg) => {
            console.log("onErrorOccurred:", code, " ", msg);
        }
        onPlaybackStateChanged: function () {
            console.log("onPlaybackStateChanged: ", mediaPlayer.errorString);
        }
        onPlayingChanged: function () {
            console.log("onPlayingChanged: ", mediaPlayer.errorString);
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
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        font.pixelSize: 60
        checkable: true
        checked: audioOutput.muted
        onToggled: audioOutput.muted = checked
        text: checked ? "🔇" : "🔊"
        ToolTip.visible: hovered
        ToolTip.text: checked ? "Unmute" : "Mute"
    }
}
