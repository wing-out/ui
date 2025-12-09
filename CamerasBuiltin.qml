import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia

Dialog {
    id: dlg
    title: "Camera & Stream Settings"
    modal: true
    standardButtons: Dialog.Ok | Dialog.Cancel

    property var streamer
    property var camera
    property var mediaDevices

    property int  tmpWidth:  streamer ? streamer.videoWidth    : 1280
    property int  tmpHeight: streamer ? streamer.videoHeight   : 720
    property int  tmpFps:    streamer ? streamer.videoFps      : 30
    property int  tmpBitrate:streamer ? streamer.bitrateKbps   : 2500
    property bool tmpFront:  camera   ? camera.position === Camera.FrontFace : true

    onOpened: {
        if (!streamer || !camera)
            return
        tmpWidth   = streamer.videoWidth
        tmpHeight  = streamer.videoHeight
        tmpFps     = streamer.videoFps
        tmpBitrate = streamer.bitrateKbps
        tmpFront   = camera.position === Camera.FrontFace
    }

    onAccepted: {
        if (!streamer || !camera)
            return
        streamer.videoWidth   = tmpWidth
        streamer.videoHeight  = tmpHeight
        streamer.videoFps     = tmpFps
        streamer.bitrateKbps  = tmpBitrate
        camera.position       = tmpFront ? Camera.FrontFace : Camera.BackFace
    }

    contentItem: ColumnLayout {
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Stream resolution"; Layout.alignment: Qt.AlignVCenter }

            SpinBox {
                Layout.fillWidth: true
                from: 160; to: 3840; stepSize: 16
                value: tmpWidth
                textFromValue: function(v) { return v + " px" }
                onValueModified: tmpWidth = value
            }

            Label { text: "x" }

            SpinBox {
                Layout.fillWidth: true
                from: 120; to: 2160; stepSize: 16
                value: tmpHeight
                textFromValue: function(v) { return v + " px" }
                onValueModified: tmpHeight = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "FPS"; Layout.alignment: Qt.AlignVCenter }
            SpinBox {
                Layout.fillWidth: true
                from: 5; to: 60; stepSize: 1
                value: tmpFps
                onValueModified: tmpFps = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Bitrate (kbps)"; Layout.alignment: Qt.AlignVCenter }
            SpinBox {
                Layout.fillWidth: true
                from: 256; to: 20000; stepSize: 128
                value: tmpBitrate
                onValueModified: tmpBitrate = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Preferred camera"; Layout.alignment: Qt.AlignVCenter }
            ComboBox {
                Layout.fillWidth: true
                model: ["Front", "Back"]
                currentIndex: tmpFront ? 0 : 1
                onCurrentIndexChanged: tmpFront = (currentIndex === 0)
            }
        }

        Label {
            Layout.fillWidth: true
            text: "Resolution/FPS apply to the RTMP stream; the actual camera format may differ."
            font.pixelSize: 11
            color: "#aaaaaa"
            wrapMode: Text.WordWrap
        }
    }
}