import QtQuick
import QtMultimedia

Rectangle {
    id: videoPlayerRTMP
    color: '#000000'
    MediaPlayer {
        id: mediaPlayer
        source: "rtmp://localhost:20096/proxy/dji-osmo-pocket3"
        autoPlay: true
        videoOutput: videoOutput
        audioOutput: AudioOutput {} // <-- Add this line
        onErrorOccurred: function (error, errorString) {
            console.log("onErrorOccurred:", error, " ", errorString);
        }
        onPlaybackStateChanged: function() {
            console.log("onPlaybackStateChanged: ", mediaPlayer.errorString)
        }
        onPlayingChanged: function() {
            console.log("onPlayingChanged: ", mediaPlayer.errorString)
        }
    }
    VideoOutput {
        id: videoOutput
        anchors.fill: parent
    }
    MouseArea {
        anchors.fill: parent
        onPressed: {
            mediaPlayer.play();
            console.log("clicked", mediaPlayer.errorString)
        }
    }
    Text {
        text: "test"
    }
}
