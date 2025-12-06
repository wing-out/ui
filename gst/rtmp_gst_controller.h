#pragma once
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QTimer>
#include <gst/gst.h>

class RtmpGstController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QObject* target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(bool autoPlay READ autoPlay WRITE setAutoPlay NOTIFY autoPlayChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)

public:
    explicit RtmpGstController(QObject* parent = nullptr);
    ~RtmpGstController() override;

    QString url() const { return m_url; }
    void setUrl(const QString& u);

    QObject* target() const { return m_target; }
    void setTarget(QObject* t);

    bool autoPlay() const { return m_autoPlay; }
    void setAutoPlay(bool v);

    bool playing() const { return m_state == GST_STATE_PLAYING; }

    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();

signals:
    void urlChanged();
    void targetChanged();
    void autoPlayChanged();
    void playingChanged();
    void errorStringChanged(const QString& message);

private:
    void ensurePipeline();
    void attachSink();
    void setState(GstState s);
    void teardown();

    void pollBus(); // non-blocking bus poll (portable)

    QString m_url;
    QPointer<QObject> m_target;
    bool m_autoPlay = true;

    GstElement* m_playbin   = nullptr;
    GstElement* m_qmlsink   = nullptr;
    GstElement* m_glsinkbin = nullptr;
    GstState    m_state     = GST_STATE_NULL;

    QTimer m_busTimer;
};
