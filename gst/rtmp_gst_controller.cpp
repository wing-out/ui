#include "RtmpGstController.h"
#include <QDebug>

RtmpGstController::RtmpGstController(QObject* parent)
    : QObject(parent)
{
    // We’ll poll the bus on the Qt event loop (portable across OSes)
    m_busTimer.setInterval(0);
    connect(&m_busTimer, &QTimer::timeout, this, &RtmpGstController::pollBus);
}

RtmpGstController::~RtmpGstController() {
    teardown();
}

void RtmpGstController::ensurePipeline() {
    if (m_playbin) return;

    // Create elements
    m_playbin   = gst_element_factory_make("playbin",   "player");
    m_qmlsink   = gst_element_factory_make("qml6glsink","qmlsink");
    m_glsinkbin = gst_element_factory_make("glsinkbin", "glsinkbin");

    if (!m_playbin || !m_qmlsink || !m_glsinkbin) {
        emit errorStringChanged("Failed to create GStreamer elements (playbin/qml6glsink/glsinkbin).");
        teardown();
        return;
    }

    // Wrap qml6glsink with glsinkbin (handles GL upload/convert)
    g_object_set(m_glsinkbin, "sink", m_qmlsink, nullptr);

    // Apply URI if already set
    if (!m_url.isEmpty()) {
        QByteArray ba = m_url.toUtf8();
        g_object_set(m_playbin, "uri", ba.constData(), nullptr);
    }

    // Route video into the GL sinkbin
    g_object_set(m_playbin, "video-sink", m_glsinkbin, nullptr);

    // Start bus polling once pipeline exists
    m_busTimer.start();
}

void RtmpGstController::attachSink() {
    if (!m_qmlsink || !m_target) return;

    // qml6glsink expects a QQuickItem* via its "widget" property
    auto *item = qobject_cast<QQuickItem*>(m_target.data());
    if (!item) {
        emit errorStringChanged("target must be a QQuickItem (e.g., GstGLVideoItem).");
        return;
    }
    g_object_set(m_qmlsink, "widget", item, nullptr);
}

void RtmpGstController::setState(GstState s) {
    if (!m_playbin) return;
    gst_element_set_state(m_playbin, s);
    m_state = s;
    emit playingChanged();
}

void RtmpGstController::teardown() {
    m_busTimer.stop();

    if (m_playbin) {
        gst_element_set_state(m_playbin, GST_STATE_NULL);
        gst_object_unref(m_playbin);
        m_playbin = nullptr;
    }
    if (m_qmlsink) {
        gst_object_unref(m_qmlsink);
        m_qmlsink = nullptr;
    }
    if (m_glsinkbin) {
        gst_object_unref(m_glsinkbin);
        m_glsinkbin = nullptr;
    }
    m_state = GST_STATE_NULL;
    emit playingChanged();
}

void RtmpGstController::setUrl(const QString& u) {
    if (m_url == u) return;
    m_url = u;
    emit urlChanged();

    ensurePipeline();
    if (!m_playbin) return;

    QByteArray ba = m_url.toUtf8();
    g_object_set(m_playbin, "uri", ba.constData(), nullptr);

    if (m_autoPlay) play();
}

void RtmpGstController::setTarget(QObject* t) {
    if (m_target == t) return;
    m_target = t;
    emit targetChanged();

    ensurePipeline();
    attachSink();
}

void RtmpGstController::setAutoPlay(bool v) {
    if (m_autoPlay == v) return;
    m_autoPlay = v;
    emit autoPlayChanged();
}

void RtmpGstController::play() {
    ensurePipeline();
    attachSink();
    if (m_playbin) setState(GST_STATE_PLAYING);
}

void RtmpGstController::pause() {
    if (m_playbin) setState(GST_STATE_PAUSED);
}

void RtmpGstController::stop() {
    if (m_playbin) setState(GST_STATE_READY);
}

void RtmpGstController::pollBus() {
    if (!m_playbin) return;

    GstBus* bus = gst_element_get_bus(m_playbin);
    if (!bus) return;

    for (;;) {
        GstMessage* msg = gst_bus_pop(bus); // non-blocking
        if (!msg) break;

        switch (GST_MESSAGE_TYPE(msg)) {
        case GST_MESSAGE_ERROR: {
            GError* err = nullptr; gchar* dbg = nullptr;
            gst_message_parse_error(msg, &err, &dbg);
            emit errorStringChanged(QStringLiteral("GStreamer error: %1").arg(err ? err->message : "unknown"));
            if (err) g_error_free(err);
            if (dbg) g_free(dbg);
            break;
        }
        case GST_MESSAGE_EOS:
            // Stream ended (for live RTMP this usually shouldn't happen)
            break;
        default:
            break;
        }
        gst_message_unref(msg);
    }
    gst_object_unref(bus);
}