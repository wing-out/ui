#ifndef MOCK_BACKEND_H
#define MOCK_BACKEND_H

#include <QObject>
#include <QQmlEngine>
#include <QJSValue>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>

// MockBackend simulates WingOutController for headless QML tests.
// It provides the same Q_INVOKABLE API surface with controllable
// canned responses, so QML pages can be tested without a real gRPC backend.
class MockBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool connected READ isConnected WRITE setConnected NOTIFY connectedChanged)
    Q_PROPERTY(QString serverUri READ serverUri WRITE setServerUri NOTIFY serverUriChanged)
    Q_PROPERTY(QString backendMode READ backendMode WRITE setBackendMode NOTIFY backendModeChanged)

public:
    explicit MockBackend(QObject *parent = nullptr) : QObject(parent) {}

    bool isConnected() const { return m_connected; }
    void setConnected(bool v) { if (m_connected != v) { m_connected = v; emit connectedChanged(); } }

    QString serverUri() const { return m_serverUri; }
    void setServerUri(const QString &v) { if (m_serverUri != v) { m_serverUri = v; emit serverUriChanged(); } }

    QString backendMode() const { return m_backendMode; }
    void setBackendMode(const QString &v) { if (m_backendMode != v) { m_backendMode = v; emit backendModeChanged(); } }

    // --- Test data setters ---
    Q_INVOKABLE void setTestBitRates(double inputVideo, double outputVideo) {
        m_bitRates[QStringLiteral("inputVideo")] = inputVideo;
        m_bitRates[QStringLiteral("outputVideo")] = outputVideo;
    }

    Q_INVOKABLE void setTestLatencies(double videoSending, double videoTranscoding) {
        m_latencies[QStringLiteral("videoSending")] = videoSending;
        m_latencies[QStringLiteral("videoTranscoding")] = videoTranscoding;
    }

    Q_INVOKABLE void setTestInputQuality(double videoContinuity) {
        m_inputQuality[QStringLiteral("videoContinuity")] = videoContinuity;
    }

    Q_INVOKABLE void setTestOutputQuality(double videoContinuity) {
        m_outputQuality[QStringLiteral("videoContinuity")] = videoContinuity;
    }

    Q_INVOKABLE void setTestFPSFraction(int num, int den) {
        m_fpsFraction[QStringLiteral("num")] = num;
        m_fpsFraction[QStringLiteral("den")] = den;
    }

    Q_INVOKABLE void setTestStats(int framesIn, int framesOut, int dropped) {
        m_stats[QStringLiteral("framesIn")] = framesIn;
        m_stats[QStringLiteral("framesOut")] = framesOut;
        m_stats[QStringLiteral("dropped")] = dropped;
    }

    Q_INVOKABLE void setTestConfig(const QString &yaml) { m_configYaml = yaml; }

    Q_INVOKABLE void setTestStreamStatus(const QString &platform, bool active, int viewers) {
        QVariantMap status;
        status[QStringLiteral("isActive")] = active;
        status[QStringLiteral("viewerCount")] = viewers;
        m_streamStatuses[platform] = status;
    }

    Q_INVOKABLE void setTestForwards(QVariantList fwds) { m_forwards = fwds; }
    Q_INVOKABLE void setTestServers(QVariantList servers) { m_servers = servers; }
    Q_INVOKABLE void setTestPlayers(QVariantList players) { m_players = players; }
    Q_INVOKABLE void setTestProfiles(QVariantList profiles) { m_profiles = profiles; }
    Q_INVOKABLE void setTestSources(QVariantList sources) { m_sources = sources; }
    Q_INVOKABLE void setTestLoggingLevel(int level) { m_loggingLevel = level; }

    Q_INVOKABLE void setTestError(const QString &method, const QString &errorMsg) {
        m_errors[method] = errorMsg;
    }
    Q_INVOKABLE void clearTestError(const QString &method) {
        m_errors.remove(method);
    }

    // --- Simulated WingOutController API ---

    Q_INVOKABLE void getBitRates(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getBitRates"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_bitRates)});
    }

    Q_INVOKABLE void getLatencies(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getLatencies"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_latencies)});
    }

    Q_INVOKABLE void getInputQuality(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getInputQuality"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_inputQuality)});
    }

    Q_INVOKABLE void getOutputQuality(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getOutputQuality"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_outputQuality)});
    }

    Q_INVOKABLE void getFPSFraction(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getFPSFraction"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_fpsFraction)});
    }

    Q_INVOKABLE void setFPSFraction(quint32 num, quint32 den, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(num); Q_UNUSED(den);
        if (invokeError(QStringLiteral("setFPSFraction"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("setFPSFraction")]++;
    }

    Q_INVOKABLE void getStats(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getStats"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_stats)});
    }

    Q_INVOKABLE void injectSubtitles(const QByteArray &data, quint64 durationNs, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(data); Q_UNUSED(durationNs);
        if (invokeError(QStringLiteral("injectSubtitles"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("injectSubtitles")]++;
    }

    Q_INVOKABLE void injectData(const QByteArray &data, quint64 durationNs, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(data); Q_UNUSED(durationNs);
        if (invokeError(QStringLiteral("injectData"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("injectData")]++;
    }

    Q_INVOKABLE void getConfig(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getConfig"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{QJSValue(m_configYaml)});
    }

    Q_INVOKABLE void setConfig(const QString &yaml, QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("setConfig"), errorCallback)) return;
        m_configYaml = yaml;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("setConfig")]++;
    }

    Q_INVOKABLE void saveConfig(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("saveConfig"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("saveConfig")]++;
    }

    Q_INVOKABLE void ping(const QString &payload, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(payload);
        if (invokeError(QStringLiteral("ping"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{QJSValue(m_pingPayload)});
        m_callCounts[QStringLiteral("ping")]++;
    }

    Q_INVOKABLE void getStreamStatus(const QString &platformId, const QString &accountId,
                                      const QString &streamId, bool noCache,
                                      QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(accountId); Q_UNUSED(streamId); Q_UNUSED(noCache);
        if (invokeError(QStringLiteral("getStreamStatus"), errorCallback)) return;
        auto status = m_streamStatuses.value(platformId).toMap();
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(status)});
    }

    Q_INVOKABLE void listStreamForwards(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("listStreamForwards"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_forwards)});
    }

    Q_INVOKABLE void listStreamServers(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("listStreamServers"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_servers)});
    }

    Q_INVOKABLE void listStreamPlayers(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("listStreamPlayers"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_players)});
    }

    Q_INVOKABLE void listProfiles(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("listProfiles"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_profiles)});
    }

    Q_INVOKABLE void listStreamSources(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("listStreamSources"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(m_sources)});
    }

    Q_INVOKABLE void addStreamSource(const QString &id, const QString &url, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id); Q_UNUSED(url);
        if (invokeError(QStringLiteral("addStreamSource"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("addStreamSource")]++;
    }

    Q_INVOKABLE void removeStreamSource(const QString &id, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id);
        if (invokeError(QStringLiteral("removeStreamSource"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("removeStreamSource")]++;
    }

    Q_INVOKABLE void stopStreamServer(const QString &id, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id);
        if (invokeError(QStringLiteral("stopStreamServer"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("stopStreamServer")]++;
    }

    Q_INVOKABLE void addStreamForward(const QString &sourceId, const QString &sinkId, bool enabled,
                                       QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(sourceId); Q_UNUSED(sinkId); Q_UNUSED(enabled);
        if (invokeError(QStringLiteral("addStreamForward"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("addStreamForward")]++;
    }

    Q_INVOKABLE void removeStreamForward(const QString &sourceId, const QString &sinkId,
                                          QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(sourceId); Q_UNUSED(sinkId);
        if (invokeError(QStringLiteral("removeStreamForward"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("removeStreamForward")]++;
    }

    Q_INVOKABLE void updateStreamForward(const QString &sourceId, const QString &sinkId, bool enabled,
                                          QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(sourceId); Q_UNUSED(sinkId); Q_UNUSED(enabled);
        if (invokeError(QStringLiteral("updateStreamForward"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("updateStreamForward")]++;
    }

    Q_INVOKABLE void startStream(const QString &platform, const QString &profile,
                                  QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(platform); Q_UNUSED(profile);
        if (invokeError(QStringLiteral("startStream"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("startStream")]++;
    }

    Q_INVOKABLE void endStream(const QString &platform, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(platform);
        if (invokeError(QStringLiteral("endStream"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("endStream")]++;
    }

    Q_INVOKABLE void applyProfile(const QString &name, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(name);
        if (invokeError(QStringLiteral("applyProfile"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("applyProfile")]++;
    }

    Q_INVOKABLE void sendChatMessage(const QString &platform, const QString &message,
                                      QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(platform); Q_UNUSED(message);
        if (invokeError(QStringLiteral("sendChatMessage"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("sendChatMessage")]++;
    }

    Q_INVOKABLE void submitOAuthCode(const QString &platform, const QString &code,
                                      QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(platform); Q_UNUSED(code);
        if (invokeError(QStringLiteral("submitOAuthCode"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("submitOAuthCode")]++;
    }

    Q_INVOKABLE void resetCache(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("resetCache"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("resetCache")]++;
    }

    Q_INVOKABLE void restart(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("restart"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("restart")]++;
    }

    Q_INVOKABLE void getLoggingLevel(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getLoggingLevel"), errorCallback)) return;
        if (callback.isCallable()) callback.call(QJSValueList{QJSValue(m_loggingLevel)});
    }

    Q_INVOKABLE void setLoggingLevel(int level, QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("setLoggingLevel"), errorCallback)) return;
        m_loggingLevel = level;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("setLoggingLevel")]++;
    }

    Q_INVOKABLE void playerSetPause(const QString &id, bool pause, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id); Q_UNUSED(pause);
        if (invokeError(QStringLiteral("playerSetPause"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("playerSetPause")]++;
    }

    Q_INVOKABLE void playerStop(const QString &id, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id);
        if (invokeError(QStringLiteral("playerStop"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("playerStop")]++;
    }

    Q_INVOKABLE void playerClose(const QString &id, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id);
        if (invokeError(QStringLiteral("playerClose"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("playerClose")]++;
    }

    Q_INVOKABLE void playerOpen(const QString &id, const QString &url, QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(id); Q_UNUSED(url);
        if (invokeError(QStringLiteral("playerOpen"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("playerOpen")]++;
    }

    Q_INVOKABLE void setBackendAddresses(const QString &ffstreamAddr, const QString &streamdAddr,
                                          QJSValue callback, QJSValue errorCallback) {
        Q_UNUSED(ffstreamAddr); Q_UNUSED(streamdAddr);
        if (invokeError(QStringLiteral("setBackendAddresses"), errorCallback)) return;
        if (callback.isCallable()) callback.call();
        m_callCounts[QStringLiteral("setBackendAddresses")]++;
    }

    Q_INVOKABLE void getBackendMode(QJSValue callback, QJSValue errorCallback) {
        if (invokeError(QStringLiteral("getBackendMode"), errorCallback)) return;
        QVariantMap result;
        result[QStringLiteral("mode")] = m_backendMode;
        if (callback.isCallable()) callback.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
    }

    // Subscription stubs
    Q_INVOKABLE void subscribeToChatMessages() {
        m_callCounts[QStringLiteral("subscribeToChatMessages")]++;
    }

    // Emit a fake chat message for testing
    Q_INVOKABLE void emitTestChatMessage(const QVariantMap &message) {
        emit chatMessageReceived(message);
    }

    // Test query helpers
    Q_INVOKABLE int callCount(const QString &method) const {
        return m_callCounts.value(method, 0);
    }

    Q_INVOKABLE void resetCallCounts() { m_callCounts.clear(); }

signals:
    void connectedChanged();
    void serverUriChanged();
    void backendModeChanged();
    void errorOccurred(const QString &error);
    void chatMessageReceived(const QVariantMap &message);

private:
    bool invokeError(const QString &method, QJSValue &errorCallback) {
        if (m_errors.contains(method)) {
            if (errorCallback.isCallable())
                errorCallback.call(QJSValueList{QJSValue(m_errors[method])});
            return true;
        }
        return false;
    }

    bool m_connected = true;
    QString m_serverUri = QStringLiteral("127.0.0.1:3595");
    QString m_backendMode = QStringLiteral("embedded");

    QVariantMap m_bitRates;
    QVariantMap m_latencies;
    QVariantMap m_inputQuality;
    QVariantMap m_outputQuality;
    QVariantMap m_fpsFraction;
    QVariantMap m_stats;
    QString m_configYaml = QStringLiteral("# test config\n");
    QVariantMap m_streamStatuses;
    QVariantList m_forwards;
    QVariantList m_servers;
    QVariantList m_players;
    QVariantList m_profiles;
    QVariantList m_sources;
    int m_loggingLevel = 5;
    QString m_pingPayload = QStringLiteral("pong");
    QMap<QString, QString> m_errors;
    QMap<QString, int> m_callCounts;
};

#endif // MOCK_BACKEND_H
