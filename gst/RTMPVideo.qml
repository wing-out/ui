import QtQuick
// The sink’s QML surface:
import org.freedesktop.gstreamer.Qt6GLVideoItem 1.0
import GstRtmp 1.0

Item {
    id: root
    property alias url: controller.url
    property alias autoPlay: controller.autoPlay
    property alias playing: controller.playing

    // Optional: expose methods to QML users
    function play() { controller.play() }
    function pause() { controller.pause() }
    function stop() { controller.stop() }

    // The GL surface qml6glsink will draw into:
    GstGLVideoItem {
        id: surface
        anchors.fill: parent
    }

    // Controller that builds the GStreamer pipeline and attaches to `surface`
    RtmpGstController {
        id: controller
        target: surface
    }
}
