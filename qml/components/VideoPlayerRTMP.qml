import QtQuick
import QtQuick.Controls
import QtMultimedia
import WingOut

Rectangle {
    id: videoPlayerRTMP
    color: "#000000"

    property string source: ""
    property bool muted: true

    property alias mediaPlayer: mediaPlayer
    property alias videoOutput: videoOutput
    property alias audioOutput: audioOutput
    property real videoFrameRate: -1

    function stop() {
        mediaPlayer.stop()
    }
    function play() {
        mediaPlayer.play()
    }
    function pause() {
        mediaPlayer.pause()
    }
    function setSource(newSource) {
        mediaPlayer.setSource(newSource)
    }

    MediaPlayer {
        id: mediaPlayer
        source: videoPlayerRTMP.source
        autoPlay: true
        playbackRate: audioOutput.muted ? 10.0 : 1.0

        Component.onCompleted: {
            var src = String(mediaPlayer.source || "").trim()
            if (src.length > 0) {
                mediaPlayer.setSource(src)
                mediaPlayer.play()
                mediaPlayer.statusLogRemaining = 12
            }
            videoPlayerRTMP.updateVideoFrameRate()
            console.log("VideoPlayerRTMP MediaPlayer source:", mediaPlayer.source)
            console.log("VideoPlayerRTMP MediaPlayer init state:", mediaPlayer.playbackState,
                        "status:", mediaPlayer.mediaStatus, "playing:", mediaPlayer.playing)
        }

        property var lastProgressAt: Date.now()
        property var lastRestartAt: 0
        property bool started: false
        property bool loggedFirstPosition: false
        property int statusLogRemaining: 0

        videoOutput: videoOutput
        audioOutput: audioOutput

        onSourceChanged: function(newSource) {
            mediaPlayer.stop()
            mediaPlayer.setSource(newSource)
            mediaPlayer.play()
            mediaPlayer.statusLogRemaining = 12
            videoPlayerRTMP.videoFrameRate = -1
        }
        onErrorOccurred: function(code, msg) {
            console.log("VideoPlayerRTMP onErrorOccurred:", code, msg)
            errorText.text = "Error: " + msg
            errorText.visible = true
        }
        onPlaybackStateChanged: {
            console.log("VideoPlayerRTMP onPlaybackStateChanged:", mediaPlayer.playbackState)
            if (mediaPlayer.playbackState === MediaPlayer.PlayingState) {
                errorText.visible = false
            }
        }
        onPlayingChanged: function() {
            console.log("VideoPlayerRTMP onPlayingChanged:", mediaPlayer.playing)
            if (!mediaPlayer.playing) {
                mediaPlayer.started = false
            }
        }
        onPositionChanged: function() {
            mediaPlayer.lastProgressAt = Date.now()
            mediaPlayer.started = true
            loadingIndicator.visible = false
            if (!mediaPlayer.loggedFirstPosition && mediaPlayer.position > 0) {
                mediaPlayer.loggedFirstPosition = true
                console.log("VideoPlayerRTMP first position:", mediaPlayer.position,
                            "source:", mediaPlayer.source)
            }
        }
        onBufferProgressChanged: function() {
            console.log("VideoPlayerRTMP bufferProgress:", mediaPlayer.bufferProgress)
            if (mediaPlayer.bufferProgress < 1.0 && !mediaPlayer.started) {
                loadingIndicator.visible = true
            }
        }
        onMetaDataChanged: function() {
            videoPlayerRTMP.updateVideoFrameRate()
        }
    }

    function updateVideoFrameRate() {
        var meta = mediaPlayer.metaData
        if (!meta) {
            videoFrameRate = -1
            return
        }
        var fpsKeys = ["videoFrameRate", "framerate", "VideoFrameRate", "frameRate", "nominalFrameRate"]
        for (var i = 0; i < fpsKeys.length; i++) {
            var key = fpsKeys[i]
            if (meta[key] !== undefined) {
                var fps = Number(meta[key])
                if (isFinite(fps) && fps > 0) {
                    videoFrameRate = fps
                    return
                }
            }
        }
        videoFrameRate = -1
    }

    // Periodic status logging during startup
    Timer {
        id: statusLogTimer
        interval: 500
        repeat: true
        running: mediaPlayer.statusLogRemaining > 0
        onTriggered: {
            console.log(
                "VideoPlayerRTMP status tick:",
                "state", mediaPlayer.playbackState,
                "status", mediaPlayer.mediaStatus,
                "playing", mediaPlayer.playing,
                "error", mediaPlayer.error,
                "errorString", mediaPlayer.errorString,
                "source", mediaPlayer.source
            )
            mediaPlayer.statusLogRemaining--
        }
    }

    // Retry timer: restarts playback when stalled or failed
    Timer {
        id: retryTimer
        interval: 100
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = Date.now()
            // If actively playing and recently received data, do nothing
            if ((mediaPlayer.playbackState === MediaPlayer.PlayingState
                 || mediaPlayer.mediaStatus === MediaPlayer.LoadingMedia)
                 && (now - mediaPlayer.lastProgressAt < 1000)) {
                return
            }
            // Throttle retries: don't restart within 10s if never started
            if (!mediaPlayer.started && (now - mediaPlayer.lastRestartAt < 10000)) {
                return
            }
            mediaPlayer.lastProgressAt = now
            mediaPlayer.lastRestartAt = now
            mediaPlayer.stop()
            var src = mediaPlayer.source
            mediaPlayer.setSource("")
            mediaPlayer.setSource(src)
            mediaPlayer.play()
            loadingIndicator.visible = true
        }
    }

    VideoOutput {
        id: videoOutput
        anchors.fill: parent
    }

    AudioOutput {
        id: audioOutput
        muted: videoPlayerRTMP.muted
    }

    // Loading indicator (visible while buffering)
    Rectangle {
        id: loadingIndicator
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: 40
        color: Qt.rgba(0, 0, 0, 0.6)
        visible: true

        BusyIndicator {
            anchors.centerIn: parent
            running: loadingIndicator.visible
            palette.dark: Theme.accentPrimary
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.bottom
            anchors.topMargin: Theme.spacingSmall
            text: "Connecting..."
            font.pixelSize: Theme.fontSmall
            color: Theme.textSecondary
        }
    }

    // Error display
    Text {
        id: errorText
        anchors.centerIn: parent
        width: parent.width - Theme.spacingLarge * 2
        visible: false
        text: ""
        font.pixelSize: Theme.fontMedium
        color: Theme.error
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
    }

    // Mute toggle button
    Rectangle {
        id: muteToggleButton
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Theme.spacingSmall
        width: 40
        height: 40
        radius: width / 2
        color: audioOutput.muted ? Qt.rgba(0, 0, 0, 0.6) : Theme.accentPrimary
        opacity: muteArea.containsMouse ? 1.0 : 0.7

        Behavior on color { ColorAnimation { duration: Theme.animFast } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }

        Text {
            anchors.centerIn: parent
            text: audioOutput.muted ? "\ue04f" : "\ue050"
            font.family: Theme.iconFont
            font.pixelSize: 22
            color: "#FFFFFF"
        }

        MouseArea {
            id: muteArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: videoPlayerRTMP.muted = !videoPlayerRTMP.muted
        }
    }
}
