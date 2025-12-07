import QtQuick
import QtQuick.Controls
import QtMultimedia

Rectangle {
    id: videoPlayerRTMP
    color: '#000000'

    property string streamName: ""

    property int portStart: 21935
    property int portEnd: 21999
    property int port: portStart
    property bool foundFreePort: false

    property alias audioMuted: audioOutput.muted
    property alias source: mediaPlayer.source

    function urlFor(p) {
        return `rtmp://0.0.0.0:${p}/${streamName}`;
    }
    function tryPort(p) {
        mediaPlayer.stop();
        mediaPlayer.source = urlFor(p);
        mediaPlayer.play();
    }

    MediaPlayer {
        id: mediaPlayer
        source: "rtmp://0.0.0.0:" + videoPlayerRTMP.port + "/" + videoPlayerRTMP.streamName
        autoPlay: true
        playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
        playbackOptions.probeSize: 2048
        playbackOptions.networkTimeoutMs: 500

        videoOutput: videoOutput
        audioOutput: AudioOutput {
            id: audioOutput
            muted: true
        }
        onErrorOccurred: (code, msg) => {
            if (videoPlayerRTMP.foundFreePort) {
                console.log("onErrorOccurred:", code, " ", msg);
                return;
            }
            if (msg.indexOf("Address already in use") === -1 || msg.indexOf("bind") === -1 || msg.indexOf("listen") === -1) {
                console.warn("Media error:", code, msg);
                return;
            }
            if (videoPlayerRTMP.port < videoPlayerRTMP.portEnd) {
                console.log("Port", videoPlayerRTMP.port, "in use, trying next port");
                videoPlayerRTMP.port += 1;
                Qt.callLater(() => tryPort(videoPlayerRTMP.port));
                return;
            }
            console.error("No free port in range", videoPlayerRTMP.portStart, "…", videoPlayerRTMP.portEnd);
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
        id: muteToggle
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
}
