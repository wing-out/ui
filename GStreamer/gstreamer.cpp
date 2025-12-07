
#include <gst/gst.h>
#include <mutex>
#include <qlogging.h>
#include <QDebug>

#include "gstreamer.h"

namespace GStreamer {

void ensure_initialized() {
  static std::once_flag flag;

  std::call_once(flag, [] {
    int argc = 0;
    char **argv = nullptr;
    gst_init(&argc, &argv);
    // Force-load the qml6 plugin so it registers Qt6GLVideoItem in QML
    GstElement *sink = gst_element_factory_make("qml6glsink", nullptr);
    if (!sink) {
      g_printerr("Failed to load GStreamer 'qml6glsink' plugin; "
                 "Qt6GLVideoItem QML type will not be available.\n");
      return;
    }
    gst_object_unref(sink);
    qDebug() << "GStreamer initialized with qml6glsink available.";
  });
}

} // namespace GStreamer