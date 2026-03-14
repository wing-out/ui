#ifndef WINGOUTCONTROLLER_H
#define WINGOUTCONTROLLER_H

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>
#include <QVariant>
#include <QGrpcHttp2Channel>
#include <QGrpcCallReply>
#include <QGrpcServerStream>
#include <QGrpcStatus>
#include <QHash>

#include <map>
#include <memory>
#include <string>

#include "wingout_client.grpc.qpb.h"

class WingOutController : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(QString serverUri READ serverUri WRITE setServerUri NOTIFY serverUriChanged)
    Q_PROPERTY(QString backendMode READ backendMode NOTIFY backendModeChanged)

public:
    explicit WingOutController(QObject *parent = nullptr);
    ~WingOutController() override;

    bool isConnected() const;
    QString serverUri() const;
    void setServerUri(const QString &uri);
    QString backendMode() const;

    // =====================================================================
    // FFStream: Monitoring
    // =====================================================================
    Q_INVOKABLE void getBitRates(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getLatencies(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getInputQuality(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getOutputQuality(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getFPSFraction(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setFPSFraction(quint32 num, quint32 den, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getStats(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void injectSubtitles(const QByteArray &data, quint64 durationNs, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void injectData(const QByteArray &data, quint64 durationNs, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Config
    // =====================================================================
    Q_INVOKABLE void getConfig(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setConfig(const QString &configYaml, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void saveConfig(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Health
    // =====================================================================
    Q_INVOKABLE void ping(const QString &payload, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Control
    // =====================================================================
    Q_INVOKABLE void getStreamStatus(const QString &platformId, const QString &accountId,
                                      const QString &streamId, bool noCache,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void listStreamForwards(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void listStreamServers(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void listStreamPlayers(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void listProfiles(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // Backend
    // =====================================================================
    Q_INVOKABLE void getBackendMode(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setBackendAddresses(const QString &ffstreamAddr, const QString &streamdAddr,
                                          const QString &avdAddr,
                                          QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getBackendAddresses(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Logging
    // =====================================================================
    Q_INVOKABLE void setLoggingLevel(int level, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getLoggingLevel(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Cache
    // =====================================================================
    Q_INVOKABLE void resetCache(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void initCache(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Lifecycle
    // =====================================================================
    Q_INVOKABLE void setStreamActive(const QString &platformId, const QString &accountId,
                                      const QString &streamId, bool active,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getStreams(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void createStream(const QString &platformId, const QString &title,
                                   const QString &description, const QString &profile,
                                   QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void deleteStream(const QString &platformId, const QString &accountId,
                                   const QString &streamId,
                                   QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getActiveStreamIDs(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void startStream(const QString &platformId, const QString &profileName,
                                  QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void endStream(const QString &platformId, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Accounts & Platforms
    // =====================================================================
    Q_INVOKABLE void getAccounts(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void isBackendEnabled(const QString &platformId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getBackendInfo(const QString &platformId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getPlatforms(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Metadata
    // =====================================================================
    Q_INVOKABLE void setTitle(const QString &platformId, const QString &title,
                               QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setDescription(const QString &platformId, const QString &description,
                                     QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Profiles
    // =====================================================================
    Q_INVOKABLE void applyProfile(const QString &profileName, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Variables
    // =====================================================================
    Q_INVOKABLE void getVariable(const QString &key, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getVariableHash(const QString &key, int hashType,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setVariable(const QString &key, const QByteArray &value,
                                  QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: OAuth
    // =====================================================================
    Q_INVOKABLE void submitOAuthCode(const QString &requestId, const QString &code,
                                      QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Servers
    // =====================================================================
    Q_INVOKABLE void startStreamServer(int serverType, const QString &listenAddr,
                                        QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void stopStreamServer(const QString &serverId, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Sources
    // =====================================================================
    Q_INVOKABLE void listStreamSources(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void addStreamSource(const QString &sourceId, const QString &url,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeStreamSource(const QString &sourceId, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Sinks
    // =====================================================================
    Q_INVOKABLE void listStreamSinks(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void addStreamSink(const QString &sinkId, int sinkType, const QString &url,
                                    QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void updateStreamSink(const QString &sinkId, int sinkType, const QString &url,
                                       QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getStreamSinkConfig(const QString &sinkId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeStreamSink(const QString &sinkId, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Forwards
    // =====================================================================
    Q_INVOKABLE void addStreamForward(const QString &sourceId, const QString &sinkId,
                                       bool enabled, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void updateStreamForward(const QString &sourceId, const QString &sinkId,
                                          bool enabled, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeStreamForward(const QString &sourceId, const QString &sinkId,
                                          QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Stream Publisher
    // =====================================================================
    Q_INVOKABLE void waitForStreamPublisher(const QString &sourceId,
                                             QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Player CRUD
    // =====================================================================
    Q_INVOKABLE void addStreamPlayer(const QString &id, const QString &title,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeStreamPlayer(const QString &playerId,
                                         QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void updateStreamPlayer(const QString &id, const QString &title,
                                         QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getStreamPlayer(const QString &playerId,
                                      QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Player Control
    // =====================================================================
    Q_INVOKABLE void playerOpen(const QString &playerId, const QString &url,
                                 QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerProcessTitle(const QString &playerId, const QString &title,
                                         QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerGetLink(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerIsEnded(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerGetPosition(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerGetLength(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerGetLag(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerSetSpeed(const QString &playerId, double speed,
                                     QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerGetSpeed(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerSetPause(const QString &playerId, bool paused,
                                     QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerStop(const QString &playerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void playerClose(const QString &playerId, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Timers
    // =====================================================================
    Q_INVOKABLE void addTimer(const QString &id, quint32 intervalSeconds,
                               const QString &actionType, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeTimer(const QString &timerId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void listTimers(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Trigger Rules
    // =====================================================================
    Q_INVOKABLE void listTriggerRules(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void addTriggerRule(const QString &id, int eventType, const QString &filter,
                                     const QString &actionType, bool enabled,
                                     QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeTriggerRule(const QString &ruleId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void updateTriggerRule(const QString &id, int eventType, const QString &filter,
                                        const QString &actionType, bool enabled,
                                        QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Events
    // =====================================================================
    Q_INVOKABLE void submitEvent(int type, const QByteArray &data,
                                  QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Chat
    // =====================================================================
    Q_INVOKABLE void sendChatMessage(const QString &platformId, const QString &message,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void removeChatMessage(const QString &platformId, const QString &messageId,
                                        QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void banUser(const QString &platformId, const QString &userId,
                              const QString &reason, quint64 durationSeconds,
                              QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: Social
    // =====================================================================
    Q_INVOKABLE void shoutout(const QString &platformId, const QString &targetUserName,
                               QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void raidTo(const QString &platformId, const QString &targetChannel,
                              QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getPeerIDs(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: AI
    // =====================================================================
    Q_INVOKABLE void llmGenerate(const QString &prompt, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // StreamD: System
    // =====================================================================
    Q_INVOKABLE void restart(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void reinitStreamControllers(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - Logging
    // =====================================================================
    Q_INVOKABLE void ffSetLoggingLevel(int level, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - Output
    // =====================================================================
    Q_INVOKABLE void removeOutput(const QString &outputId, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getCurrentOutput(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void switchOutputByProps(const QVariantMap &props,
                                          QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - SRT
    // =====================================================================
    Q_INVOKABLE void getOutputSRTStats(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getSRTFlagInt(int flag, QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setSRTFlagInt(int flag, qint64 value, QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - End
    // =====================================================================
    Q_INVOKABLE void ffEnd(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - Pipelines
    // =====================================================================
    Q_INVOKABLE void getPipelines(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - Auto BitRate
    // =====================================================================
    Q_INVOKABLE void getVideoAutoBitRateConfig(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setVideoAutoBitRateConfig(quint64 minBitrate, quint64 maxBitrate,
                                                double targetFps,
                                                QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getVideoAutoBitRateCalculator(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setVideoAutoBitRateCalculator(const QString &type, const QByteArray &config,
                                                    QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // FFStream: Extended - Inputs
    // =====================================================================
    Q_INVOKABLE void getInputsInfo(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setInputCustomOption(const QString &inputId, const QString &key,
                                           const QString &value,
                                           QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void setStopInput(const QString &inputId, bool stop,
                                   QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // Channel Quality
    // =====================================================================
    Q_INVOKABLE void setChannelQuality(const QVariantList &channels,
                                        QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void getChannelQuality(QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // AVD Management
    // =====================================================================
    Q_INVOKABLE void avdListRoutes(QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void avdGetPrivacyBlur(const QString &routePath, qint32 forwardingIndex,
                                        QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void avdSetPrivacyBlur(const QString &routePath, qint32 forwardingIndex,
                                        const QVariantMap &params,
                                        QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void avdGetDeblemish(const QString &routePath, qint32 forwardingIndex,
                                      QJSValue callback, QJSValue errorCallback);
    Q_INVOKABLE void avdSetDeblemish(const QString &routePath, qint32 forwardingIndex,
                                      const QVariantMap &params,
                                      QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // Diagnostics
    // =====================================================================
    Q_INVOKABLE void injectDiagnostics(const QVariantMap &diagnostics,
                                        QJSValue callback, QJSValue errorCallback);

    // =====================================================================
    // Embedded Daemon
    // =====================================================================
    Q_INVOKABLE QString startEmbeddedDaemon(const QString &streamdAddr, const QString &ffstreamAddr);
    Q_INVOKABLE void stopEmbeddedDaemon();
    Q_INVOKABLE bool isEmbeddedDaemonRunning();
    Q_INVOKABLE void setStopDaemonOnClose(bool stop);

    // =====================================================================
    // Server-Streaming Subscriptions
    // =====================================================================
    Q_INVOKABLE void subscribeToChatMessages();
    Q_INVOKABLE void subscribeToConfigChanges();
    Q_INVOKABLE void subscribeToStreamsChanges();
    Q_INVOKABLE void subscribeToOAuthRequests();
    Q_INVOKABLE void subscribeToStreamServersChanges();
    Q_INVOKABLE void subscribeToStreamSourcesChanges();
    Q_INVOKABLE void subscribeToStreamSinksChanges();
    Q_INVOKABLE void subscribeToStreamForwardsChanges();
    Q_INVOKABLE void subscribeToStreamPlayersChanges();
    Q_INVOKABLE void subscribeToVariable(const QString &key);
    Q_INVOKABLE void subscribeToPlayerEnd(const QString &playerId);
    Q_INVOKABLE void unsubscribeAll();

signals:
    void connectedChanged();
    void serverUriChanged();
    void backendModeChanged();
    void errorOccurred(const QString &error);

    // Subscription signals
    void chatMessageReceived(const QVariantMap &message);
    void configChanged(const QString &configYaml);
    void streamsChanged();
    void oauthRequestReceived(const QVariantMap &request);
    void streamServersChanged();
    void streamSourcesChanged();
    void streamSinksChanged();
    void streamForwardsChanged();
    void streamPlayersChanged();
    void variableChanged(const QString &key, const QByteArray &value);
    void streamPlayerEnded(const QString &playerId);

private:
    void connectToServer();
    void handleGrpcError(const QGrpcStatus &status, QJSValue &errCb);

    bool m_connected = false;
    QString m_serverUri;
    QString m_backendMode;

    std::shared_ptr<QGrpcHttp2Channel> m_channel;
    std::unique_ptr<wingout::WingOutService::Client> m_client;

    // Active server-streaming subscriptions
    std::unique_ptr<QGrpcServerStream> m_chatStream;
    std::unique_ptr<QGrpcServerStream> m_configStream;
    std::unique_ptr<QGrpcServerStream> m_streamsStream;
    std::unique_ptr<QGrpcServerStream> m_oauthStream;
    std::unique_ptr<QGrpcServerStream> m_serversStream;
    std::unique_ptr<QGrpcServerStream> m_sourcesStream;
    std::unique_ptr<QGrpcServerStream> m_sinksStream;
    std::unique_ptr<QGrpcServerStream> m_forwardsStream;
    std::unique_ptr<QGrpcServerStream> m_playersStream;
    std::map<std::string, std::unique_ptr<QGrpcServerStream>> m_variableStreams;
    std::map<std::string, std::unique_ptr<QGrpcServerStream>> m_playerEndStreams;
};

#endif // WINGOUTCONTROLLER_H
