#include "wingoutcontroller.h"
#include <QDebug>
#include <QJSEngine>
#include <QUrl>

WingOutController::WingOutController(QObject *parent)
    : QObject(parent)
{
}

WingOutController::~WingOutController()
{
    unsubscribeAll();
}

bool WingOutController::isConnected() const { return m_connected; }

QString WingOutController::serverUri() const { return m_serverUri; }

void WingOutController::setServerUri(const QString &uri)
{
    if (m_serverUri == uri) return;
    m_serverUri = uri;
    emit serverUriChanged();
    connectToServer();
}

void WingOutController::connectToServer()
{
    if (m_serverUri.isEmpty()) {
        m_connected = false;
        emit connectedChanged();
        return;
    }

    QString grpcUrl = m_serverUri;
    if (!grpcUrl.startsWith(QStringLiteral("http"))) {
        grpcUrl = QStringLiteral("http://") + grpcUrl;
    }

    m_channel = std::make_shared<QGrpcHttp2Channel>(QUrl(grpcUrl));
    m_client = std::make_unique<wingout::WingOutService::Client>();
    m_client->attachChannel(m_channel);

    // Verify connectivity with GetBackendAddresses (always succeeds when wingoutd is reachable,
    // unlike Ping which requires streamd to be configured).
    auto reply = std::shared_ptr<QGrpcCallReply>(
        m_client->GetBackendAddresses(wingout::GetBackendAddressesRequest{}));
    connect(reply.get(), &QGrpcCallReply::finished, this,
        [this, grpcUrl, reply](const QGrpcStatus &status) {
            if (status.isOk()) {
                if (!m_connected) {
                    m_connected = true;
                    emit connectedChanged();
                }
                qDebug() << "gRPC client verified connection to" << grpcUrl;
            } else {
                if (m_connected) {
                    m_connected = false;
                    emit connectedChanged();
                }
                emit errorOccurred(QStringLiteral("Cannot connect to backend at ") + grpcUrl
                    + QStringLiteral(": ") + status.message());
                qWarning() << "gRPC connection check failed for" << grpcUrl << ":" << status.message();
            }
        });
}

QString WingOutController::backendMode() const { return m_backendMode; }

void WingOutController::handleGrpcError(const QGrpcStatus &status, QJSValue &errCb)
{
    QString msg = status.message();
    emit errorOccurred(msg);
    if (errCb.isCallable())
        errCb.call(QJSValueList{QJSValue(msg)});
}

// Helper macro: connect finished signal on a shared_ptr reply.
// In Qt 6.10.1, QGrpcOperation::finished(const QGrpcStatus &) is the only signal;
// check isOk() to distinguish success from error.
// reply must be std::shared_ptr<QGrpcCallReply>.
#define GRPC_CONNECT_REPLY(reply, successBody)                                       \
    connect(reply.get(), &QGrpcCallReply::finished, this,                            \
        [this, cb = std::move(callback), errCb = std::move(errorCallback), reply]    \
        (const QGrpcStatus &_grpc_status) mutable {                                  \
            if (_grpc_status.isOk()) {                                               \
                successBody                                                          \
            } else {                                                                 \
                handleGrpcError(_grpc_status, errCb);                                \
            }                                                                        \
        });

// Helper macro: standard "not connected" guard at the start of every method.
#define GRPC_CHECK_CLIENT()                                                          \
    if (!m_client) {                                                                 \
        if (errorCallback.isCallable())                                              \
            errorCallback.call(QJSValueList{QJSValue(QStringLiteral("Not connected"))});\
        return;                                                                      \
    }

// =========================================================================
// FFStream: Monitoring
// =========================================================================

void WingOutController::getBitRates(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetBitRates(wingout::GetBitRatesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetBitRatesReply>()) {
            QVariantMap result;
            result[QStringLiteral("inputVideo")] = static_cast<qint64>(resp->inputBitRate().video());
            result[QStringLiteral("inputAudio")] = static_cast<qint64>(resp->inputBitRate().audio());
            result[QStringLiteral("encodedVideo")] = static_cast<qint64>(resp->encodedBitRate().video());
            result[QStringLiteral("encodedAudio")] = static_cast<qint64>(resp->encodedBitRate().audio());
            result[QStringLiteral("outputVideo")] = static_cast<qint64>(resp->outputBitRate().video());
            result[QStringLiteral("outputAudio")] = static_cast<qint64>(resp->outputBitRate().audio());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getLatencies(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetLatencies(wingout::GetLatenciesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetLatenciesReply>()) {
            QVariantMap result;
            result[QStringLiteral("videoPreTranscoding")] = static_cast<qint64>(resp->video().preTranscodingUs());
            result[QStringLiteral("videoTranscoding")] = static_cast<qint64>(resp->video().transcodingUs());
            result[QStringLiteral("videoTranscodedPreSend")] = static_cast<qint64>(resp->video().transcodedPreSendUs());
            result[QStringLiteral("videoSending")] = static_cast<qint64>(resp->video().sendingUs());
            result[QStringLiteral("audioPreTranscoding")] = static_cast<qint64>(resp->audio().preTranscodingUs());
            result[QStringLiteral("audioTranscoding")] = static_cast<qint64>(resp->audio().transcodingUs());
            result[QStringLiteral("audioSending")] = static_cast<qint64>(resp->audio().sendingUs());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getInputQuality(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetInputQuality(wingout::GetInputQualityRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetInputQualityReply>()) {
            QVariantMap result;
            result[QStringLiteral("videoContinuity")] = resp->video().continuity();
            result[QStringLiteral("videoFrameRate")] = resp->video().frameRate();
            result[QStringLiteral("videoOverlap")] = resp->video().overlap();
            result[QStringLiteral("videoInvalidDts")] = static_cast<qint64>(resp->video().invalidDts());
            result[QStringLiteral("audioContinuity")] = resp->audio().continuity();
            result[QStringLiteral("audioFrameRate")] = resp->audio().frameRate();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getOutputQuality(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetOutputQuality(wingout::GetOutputQualityRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetOutputQualityReply>()) {
            QVariantMap result;
            result[QStringLiteral("videoContinuity")] = resp->video().continuity();
            result[QStringLiteral("videoFrameRate")] = resp->video().frameRate();
            result[QStringLiteral("videoOverlap")] = resp->video().overlap();
            result[QStringLiteral("audioContinuity")] = resp->audio().continuity();
            result[QStringLiteral("audioFrameRate")] = resp->audio().frameRate();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getFPSFraction(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetFPSFraction(wingout::GetFPSFractionRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetFPSFractionReply>()) {
            QVariantMap result;
            result[QStringLiteral("num")] = resp->num();
            result[QStringLiteral("den")] = resp->den();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::setFPSFraction(quint32 num, quint32 den, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetFPSFractionRequest req;
    req.setNum(num);
    req.setDen(den);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetFPSFraction(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getStats(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetStats(wingout::GetStatsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetStatsReply>()) {
            QVariantMap result;
            result[QStringLiteral("receivedPackets")] = static_cast<qint64>(resp->receivedPackets());
            result[QStringLiteral("receivedFrames")] = static_cast<qint64>(resp->receivedFrames());
            result[QStringLiteral("processedPackets")] = static_cast<qint64>(resp->processedPackets());
            result[QStringLiteral("processedFrames")] = static_cast<qint64>(resp->processedFrames());
            result[QStringLiteral("sentPackets")] = static_cast<qint64>(resp->sentPackets());
            result[QStringLiteral("sentFrames")] = static_cast<qint64>(resp->sentFrames());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::injectSubtitles(const QByteArray &data, quint64 durationNs,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::InjectSubtitlesRequest req;
    req.setData(data);
    req.setDurationNs(durationNs);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->InjectSubtitles(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::injectData(const QByteArray &data, quint64 durationNs,
                                    QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::InjectDataRequest req;
    req.setData(data);
    req.setDurationNs(durationNs);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->InjectData(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Config
// =========================================================================

void WingOutController::getConfig(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetConfig(wingout::GetConfigRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetConfigReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->config())});
        }
    });
}

void WingOutController::setConfig(const QString &configYaml, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetConfigRequest req;
    req.setConfig(configYaml);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetConfig(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::saveConfig(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SaveConfig(wingout::SaveConfigRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Health
// =========================================================================

void WingOutController::ping(const QString &payload, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::PingRequest req;
    req.setPayload(payload);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->Ping(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::PingReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->payload())});
        }
    });
}

// =========================================================================
// StreamD: Stream Control
// =========================================================================

void WingOutController::getStreamStatus(const QString &platformId, const QString &accountId,
                                          const QString &streamId, bool noCache,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetStreamStatusRequest req;
    req.setPlatformId(platformId);
    req.setAccountId(accountId);
    req.setStreamId(streamId);
    req.setNoCache(noCache);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetStreamStatus(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetStreamStatusReply>()) {
            QVariantMap result;
            result[QStringLiteral("isActive")] = resp->isActive();
            result[QStringLiteral("viewersCount")] = resp->hasViewersCount()
                ? static_cast<qint64>(resp->viewersCount()) : -1;
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::listStreamForwards(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListStreamForwards(wingout::ListStreamForwardsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListStreamForwardsReply>()) {
            QVariantList list;
            for (const auto &fwd : resp->forwards()) {
                QVariantMap item;
                item[QStringLiteral("sourceId")] = fwd.sourceId();
                item[QStringLiteral("sinkId")] = fwd.sinkId();
                item[QStringLiteral("sinkType")] = fwd.sinkType();
                item[QStringLiteral("enabled")] = fwd.enabled();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::listStreamServers(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListStreamServers(wingout::ListStreamServersRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListStreamServersReply>()) {
            QVariantList list;
            for (const auto &srv : resp->servers()) {
                QVariantMap item;
                item[QStringLiteral("id")] = srv.id_proto();
                item[QStringLiteral("type")] = srv.type();
                item[QStringLiteral("listenAddr")] = srv.listenAddr();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::listStreamPlayers(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListStreamPlayers(wingout::ListStreamPlayersRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListStreamPlayersReply>()) {
            QVariantList list;
            for (const auto &player : resp->players()) {
                QVariantMap item;
                item[QStringLiteral("id")] = player.id_proto();
                item[QStringLiteral("title")] = player.title();
                item[QStringLiteral("link")] = player.link();
                item[QStringLiteral("position")] = player.position();
                item[QStringLiteral("length")] = player.length();
                item[QStringLiteral("isPaused")] = player.isPaused();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::listProfiles(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListProfiles(wingout::ListProfilesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListProfilesReply>()) {
            QVariantList list;
            for (const auto &profile : resp->profiles()) {
                QVariantMap item;
                item[QStringLiteral("name")] = profile.name();
                item[QStringLiteral("description")] = profile.description();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// Backend
// =========================================================================

void WingOutController::getBackendMode(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetBackendMode(wingout::GetBackendModeRequest{}));
    connect(reply.get(), &QGrpcCallReply::finished, this,
        [this, cb = std::move(callback), errCb = std::move(errorCallback), reply]
        (const QGrpcStatus &_grpc_status) mutable {
            if (_grpc_status.isOk()) {
                if (auto resp = reply->read<wingout::GetBackendModeReply>()) {
                    m_backendMode = resp->mode();
                    emit backendModeChanged();
                    if (cb.isCallable())
                        cb.call(QJSValueList{QJSValue(resp->mode())});
                }
            } else {
                handleGrpcError(_grpc_status, errCb);
            }
        });
}

void WingOutController::setBackendAddresses(const QString &ffstreamAddr, const QString &streamdAddr,
                                              const QString &avdAddr,
                                              QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetBackendAddressesRequest req;
    req.setFfstreamAddr(ffstreamAddr);
    req.setStreamdAddr(streamdAddr);
    req.setAvdAddr(avdAddr);

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetBackendAddresses(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getBackendAddresses(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetBackendAddresses(wingout::GetBackendAddressesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetBackendAddressesReply>()) {
            QVariantMap result;
            result[QStringLiteral("ffstreamAddr")] = resp->ffstreamAddr();
            result[QStringLiteral("streamdAddr")] = resp->streamdAddr();
            result[QStringLiteral("avdAddr")] = resp->avdAddr();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

// =========================================================================
// StreamD: Logging
// =========================================================================

void WingOutController::setLoggingLevel(int level, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetLoggingLevelRequest req;
    req.setLevel(static_cast<wingout::LoggingLevelGadget::LoggingLevel>(level));
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetLoggingLevel(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getLoggingLevel(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetLoggingLevel(wingout::GetLoggingLevelRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetLoggingLevelReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(static_cast<int>(resp->level()))});
        }
    });
}

// =========================================================================
// StreamD: Cache
// =========================================================================

void WingOutController::resetCache(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ResetCache(wingout::ResetCacheRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::initCache(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->InitCache(wingout::InitCacheRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Lifecycle
// =========================================================================

void WingOutController::setStreamActive(const QString &platformId, const QString &accountId,
                                          const QString &streamId, bool active,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetStreamActiveRequest req;
    wingout::StreamIDFullyQualifiedProto streamIdProto;
    streamIdProto.setPlatformId(platformId);
    streamIdProto.setAccountId(accountId);
    streamIdProto.setStreamId(streamId);
    req.setStreamId(streamIdProto);
    req.setActive(active);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetStreamActive(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getStreams(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetStreams(wingout::GetStreamsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetStreamsReply>()) {
            QVariantList list;
            for (const auto &stream : resp->streams()) {
                QVariantMap item;
                item[QStringLiteral("platformId")] = stream.id_proto().platformId();
                item[QStringLiteral("accountId")] = stream.id_proto().accountId();
                item[QStringLiteral("streamId")] = stream.id_proto().streamId();
                item[QStringLiteral("isActive")] = stream.isActive();
                item[QStringLiteral("title")] = stream.title();
                item[QStringLiteral("description")] = stream.description();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::createStream(const QString &platformId, const QString &title,
                                       const QString &description, const QString &profile,
                                       QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::CreateStreamRequest req;
    req.setPlatformId(platformId);
    req.setTitle(title);
    req.setDescription(description);
    req.setProfile(profile);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->CreateStream(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::CreateStreamReply>()) {
            QVariantMap result;
            result[QStringLiteral("platformId")] = resp->streamId().platformId();
            result[QStringLiteral("accountId")] = resp->streamId().accountId();
            result[QStringLiteral("streamId")] = resp->streamId().streamId();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::deleteStream(const QString &platformId, const QString &accountId,
                                       const QString &streamId,
                                       QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::DeleteStreamRequest req;
    wingout::StreamIDFullyQualifiedProto streamIdProto;
    streamIdProto.setPlatformId(platformId);
    streamIdProto.setAccountId(accountId);
    streamIdProto.setStreamId(streamId);
    req.setStreamId(streamIdProto);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->DeleteStream(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getActiveStreamIDs(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetActiveStreamIDs(wingout::GetActiveStreamIDsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetActiveStreamIDsReply>()) {
            QVariantList list;
            for (const auto &sid : resp->streamIds()) {
                QVariantMap item;
                item[QStringLiteral("platformId")] = sid.platformId();
                item[QStringLiteral("accountId")] = sid.accountId();
                item[QStringLiteral("streamId")] = sid.streamId();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::startStream(const QString &platformId, const QString &profileName,
                                      QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StartStreamRequest req;
    req.setPlatformId(platformId);
    req.setProfileName(profileName);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StartStream(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::endStream(const QString &platformId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::EndStreamRequest req;
    req.setPlatformId(platformId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->EndStream(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Accounts & Platforms
// =========================================================================

void WingOutController::getAccounts(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetAccounts(wingout::GetAccountsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetAccountsReply>()) {
            QVariantList list;
            for (const auto &acct : resp->accounts()) {
                QVariantMap item;
                item[QStringLiteral("platformId")] = acct.platformId();
                item[QStringLiteral("accountId")] = acct.accountId();
                item[QStringLiteral("isEnabled")] = acct.isEnabled();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::isBackendEnabled(const QString &platformId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::IsBackendEnabledRequest req;
    req.setPlatformId(platformId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->IsBackendEnabled(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::IsBackendEnabledReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->enabled())});
        }
    });
}

void WingOutController::getBackendInfo(const QString &platformId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetBackendInfoRequest req;
    req.setPlatformId(platformId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetBackendInfo(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetBackendInfoReply>()) {
            QVariantMap result;
            result[QStringLiteral("platformId")] = resp->platformId();
            QVariantList caps;
            for (const auto &cap : resp->capabilities()) {
                caps.append(static_cast<int>(cap));
            }
            result[QStringLiteral("capabilities")] = caps;
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getPlatforms(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetPlatforms(wingout::GetPlatformsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetPlatformsReply>()) {
            QVariantList list;
            for (const auto &pid : resp->platformIds()) {
                list.append(pid);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// StreamD: Metadata
// =========================================================================

void WingOutController::setTitle(const QString &platformId, const QString &title,
                                   QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetTitleRequest req;
    req.setPlatformId(platformId);
    req.setTitle(title);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetTitle(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::setDescription(const QString &platformId, const QString &description,
                                         QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetDescriptionRequest req;
    req.setPlatformId(platformId);
    req.setDescription(description);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetDescription(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Profiles
// =========================================================================

void WingOutController::applyProfile(const QString &profileName, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::ApplyProfileRequest req;
    req.setProfileName(profileName);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ApplyProfile(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Variables
// =========================================================================

void WingOutController::getVariable(const QString &key, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetVariableRequest req;
    req.setKey(key);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetVariable(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetVariableReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(QString::fromUtf8(resp->value()))});
        }
    });
}

void WingOutController::getVariableHash(const QString &key, int hashType,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetVariableHashRequest req;
    req.setKey(key);
    req.setHashType(static_cast<wingout::HashTypeGadget::HashType>(hashType));
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetVariableHash(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetVariableHashReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->hash())});
        }
    });
}

void WingOutController::setVariable(const QString &key, const QByteArray &value,
                                      QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetVariableRequest req;
    req.setKey(key);
    req.setValue(value);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetVariable(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: OAuth
// =========================================================================

void WingOutController::submitOAuthCode(const QString &requestId, const QString &code,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SubmitOAuthCodeRequest req;
    req.setRequestId(requestId);
    req.setCode(code);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SubmitOAuthCode(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Servers
// =========================================================================

void WingOutController::startStreamServer(int serverType, const QString &listenAddr,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StartStreamServerRequest req;
    req.setServerType(static_cast<wingout::StreamServerTypeGadget::StreamServerType>(serverType));
    req.setListenAddr(listenAddr);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StartStreamServer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StartStreamServerReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->serverId())});
        }
    });
}

void WingOutController::stopStreamServer(const QString &serverId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StopStreamServerRequest req;
    req.setServerId(serverId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StopStreamServer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Sources
// =========================================================================

void WingOutController::listStreamSources(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListStreamSources(wingout::ListStreamSourcesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListStreamSourcesReply>()) {
            QVariantList list;
            for (const auto &src : resp->sources()) {
                QVariantMap item;
                item[QStringLiteral("id")] = src.id_proto();
                item[QStringLiteral("url")] = src.url();
                item[QStringLiteral("isActive")] = src.isActive();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::addStreamSource(const QString &sourceId, const QString &url,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddStreamSourceRequest req;
    req.setSourceId(sourceId);
    req.setUrl(url);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddStreamSource(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::removeStreamSource(const QString &sourceId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveStreamSourceRequest req;
    req.setSourceId(sourceId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveStreamSource(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Sinks
// =========================================================================

void WingOutController::listStreamSinks(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListStreamSinks(wingout::ListStreamSinksRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListStreamSinksReply>()) {
            QVariantList list;
            for (const auto &sink : resp->sinks()) {
                QVariantMap item;
                item[QStringLiteral("id")] = sink.id_proto();
                item[QStringLiteral("sinkType")] = static_cast<int>(sink.sinkType());
                item[QStringLiteral("url")] = sink.url();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::addStreamSink(const QString &sinkId, int sinkType, const QString &url,
                                        QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddStreamSinkRequest req;
    req.setSinkId(sinkId);
    req.setSinkType(static_cast<wingout::StreamSinkTypeGadget::StreamSinkType>(sinkType));
    req.setUrl(url);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddStreamSink(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::updateStreamSink(const QString &sinkId, int sinkType, const QString &url,
                                           QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::UpdateStreamSinkRequest req;
    req.setSinkId(sinkId);
    req.setSinkType(static_cast<wingout::StreamSinkTypeGadget::StreamSinkType>(sinkType));
    req.setUrl(url);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->UpdateStreamSink(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getStreamSinkConfig(const QString &sinkId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetStreamSinkConfigRequest req;
    req.setSinkId(sinkId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetStreamSinkConfig(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetStreamSinkConfigReply>()) {
            QVariantMap result;
            result[QStringLiteral("url")] = resp->config().url();
            QVariantMap encoder;
            encoder[QStringLiteral("audioCodec")] = static_cast<int>(resp->config().encoder().audioCodec());
            encoder[QStringLiteral("videoCodec")] = static_cast<int>(resp->config().encoder().videoCodec());
            encoder[QStringLiteral("audioBitrate")] = static_cast<qint64>(resp->config().encoder().audioBitrate());
            encoder[QStringLiteral("videoBitrate")] = static_cast<qint64>(resp->config().encoder().videoBitrate());
            encoder[QStringLiteral("videoWidth")] = resp->config().encoder().videoWidth();
            encoder[QStringLiteral("videoHeight")] = resp->config().encoder().videoHeight();
            result[QStringLiteral("encoder")] = encoder;
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::removeStreamSink(const QString &sinkId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveStreamSinkRequest req;
    req.setSinkId(sinkId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveStreamSink(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Forwards
// =========================================================================

void WingOutController::addStreamForward(const QString &sourceId, const QString &sinkId,
                                           bool enabled, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddStreamForwardRequest req;
    req.setSourceId(sourceId);
    req.setSinkId(sinkId);
    req.setEnabled(enabled);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddStreamForward(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::updateStreamForward(const QString &sourceId, const QString &sinkId,
                                              bool enabled, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::UpdateStreamForwardRequest req;
    req.setSourceId(sourceId);
    req.setSinkId(sinkId);
    req.setEnabled(enabled);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->UpdateStreamForward(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::removeStreamForward(const QString &sourceId, const QString &sinkId,
                                              QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveStreamForwardRequest req;
    req.setSourceId(sourceId);
    req.setSinkId(sinkId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveStreamForward(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Stream Publisher
// =========================================================================

void WingOutController::waitForStreamPublisher(const QString &sourceId,
                                                 QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::WaitForStreamPublisherRequest req;
    req.setSourceId(sourceId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->WaitForStreamPublisher(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Player CRUD
// =========================================================================

void WingOutController::addStreamPlayer(const QString &id, const QString &title,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddStreamPlayerRequest req;
    wingout::StreamPlayerProto player;
    player.setId_proto(id);
    player.setTitle(title);
    req.setPlayer(player);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddStreamPlayer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AddStreamPlayerReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->playerId())});
        }
    });
}

void WingOutController::removeStreamPlayer(const QString &playerId,
                                             QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveStreamPlayerRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveStreamPlayer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::updateStreamPlayer(const QString &id, const QString &title,
                                             QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::UpdateStreamPlayerRequest req;
    wingout::StreamPlayerProto player;
    player.setId_proto(id);
    player.setTitle(title);
    req.setPlayer(player);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->UpdateStreamPlayer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getStreamPlayer(const QString &playerId,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetStreamPlayerRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetStreamPlayer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetStreamPlayerReply>()) {
            QVariantMap result;
            result[QStringLiteral("id")] = resp->player().id_proto();
            result[QStringLiteral("title")] = resp->player().title();
            result[QStringLiteral("link")] = resp->player().link();
            result[QStringLiteral("position")] = resp->player().position();
            result[QStringLiteral("length")] = resp->player().length();
            result[QStringLiteral("isPaused")] = resp->player().isPaused();
            result[QStringLiteral("speed")] = resp->player().speed();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

// =========================================================================
// StreamD: Player Control
// =========================================================================

void WingOutController::playerOpen(const QString &playerId, const QString &url,
                                     QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerOpenRequest req;
    req.setPlayerId(playerId);
    req.setUrl(url);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerOpen(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::playerProcessTitle(const QString &playerId, const QString &title,
                                             QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerProcessTitleRequest req;
    req.setPlayerId(playerId);
    req.setTitle(title);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerProcessTitle(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::playerGetLink(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerGetLinkRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerGetLink(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerGetLinkReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->url())});
        }
    });
}

void WingOutController::playerIsEnded(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerIsEndedRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerIsEnded(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerIsEndedReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->isEnded())});
        }
    });
}

void WingOutController::playerGetPosition(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerGetPositionRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerGetPosition(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerGetPositionReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->seconds())});
        }
    });
}

void WingOutController::playerGetLength(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerGetLengthRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerGetLength(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerGetLengthReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->seconds())});
        }
    });
}

void WingOutController::playerGetLag(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerGetLagRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerGetLag(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerGetLagReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->seconds())});
        }
    });
}

void WingOutController::playerSetSpeed(const QString &playerId, double speed,
                                         QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerSetSpeedRequest req;
    req.setPlayerId(playerId);
    req.setSpeed(speed);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerSetSpeed(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::playerGetSpeed(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerGetSpeedRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerGetSpeed(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::StreamPlayerGetSpeedReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->speed())});
        }
    });
}

void WingOutController::playerSetPause(const QString &playerId, bool paused,
                                         QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerSetPauseRequest req;
    req.setPlayerId(playerId);
    req.setPaused(paused);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerSetPause(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::playerStop(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerStopRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerStop(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::playerClose(const QString &playerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::StreamPlayerCloseRequest req;
    req.setPlayerId(playerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->StreamPlayerClose(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Timers
// =========================================================================

void WingOutController::addTimer(const QString &id, quint32 intervalSeconds,
                                   const QString &actionType, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddTimerRequest req;
    wingout::TimerProto timer;
    timer.setId_proto(id);
    timer.setIntervalSeconds(intervalSeconds);
    wingout::ActionProto action;
    action.setType(actionType);
    timer.setAction(action);
    req.setTimer(timer);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddTimer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AddTimerReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->timerId())});
        }
    });
}

void WingOutController::removeTimer(const QString &timerId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveTimerRequest req;
    req.setTimerId(timerId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveTimer(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::listTimers(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListTimers(wingout::ListTimersRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListTimersReply>()) {
            QVariantList list;
            for (const auto &t : resp->timers()) {
                QVariantMap item;
                item[QStringLiteral("id")] = t.id_proto();
                item[QStringLiteral("intervalSeconds")] = t.intervalSeconds();
                item[QStringLiteral("actionType")] = t.action().type();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// StreamD: Trigger Rules
// =========================================================================

void WingOutController::listTriggerRules(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->ListTriggerRules(wingout::ListTriggerRulesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::ListTriggerRulesReply>()) {
            QVariantList list;
            for (const auto &rule : resp->rules()) {
                QVariantMap item;
                item[QStringLiteral("id")] = rule.id_proto();
                item[QStringLiteral("eventType")] = static_cast<int>(rule.eventQuery().eventType());
                item[QStringLiteral("filter")] = rule.eventQuery().filter();
                item[QStringLiteral("actionType")] = rule.action().type();
                item[QStringLiteral("enabled")] = rule.enabled();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::addTriggerRule(const QString &id, int eventType, const QString &filter,
                                         const QString &actionType, bool enabled,
                                         QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AddTriggerRuleRequest req;
    wingout::TriggerRuleProto rule;
    rule.setId_proto(id);
    wingout::EventQueryProto eventQuery;
    eventQuery.setEventType(static_cast<wingout::EventTypeGadget::EventType>(eventType));
    eventQuery.setFilter(filter);
    rule.setEventQuery(eventQuery);
    wingout::ActionProto action;
    action.setType(actionType);
    rule.setAction(action);
    rule.setEnabled(enabled);
    req.setRule(rule);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AddTriggerRule(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AddTriggerRuleReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->ruleId())});
        }
    });
}

void WingOutController::removeTriggerRule(const QString &ruleId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveTriggerRuleRequest req;
    req.setRuleId(ruleId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveTriggerRule(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::updateTriggerRule(const QString &id, int eventType, const QString &filter,
                                            const QString &actionType, bool enabled,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::UpdateTriggerRuleRequest req;
    wingout::TriggerRuleProto rule;
    rule.setId_proto(id);
    wingout::EventQueryProto eventQuery;
    eventQuery.setEventType(static_cast<wingout::EventTypeGadget::EventType>(eventType));
    eventQuery.setFilter(filter);
    rule.setEventQuery(eventQuery);
    wingout::ActionProto action;
    action.setType(actionType);
    rule.setAction(action);
    rule.setEnabled(enabled);
    req.setRule(rule);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->UpdateTriggerRule(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Events
// =========================================================================

void WingOutController::submitEvent(int type, const QByteArray &data,
                                      QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SubmitEventRequest req;
    wingout::EventProto event;
    event.setType(static_cast<wingout::EventTypeGadget::EventType>(type));
    event.setData(data);
    req.setEvent(event);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SubmitEvent(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Chat
// =========================================================================

void WingOutController::sendChatMessage(const QString &platformId, const QString &message,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SendChatMessageRequest req;
    req.setPlatformId(platformId);
    req.setMessage(message);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SendChatMessage(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::removeChatMessage(const QString &platformId, const QString &messageId,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveChatMessageRequest req;
    req.setPlatformId(platformId);
    req.setMessageId(messageId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveChatMessage(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::banUser(const QString &platformId, const QString &userId,
                                  const QString &reason, quint64 durationSeconds,
                                  QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::BanUserRequest req;
    req.setPlatformId(platformId);
    req.setUserId(userId);
    req.setReason(reason);
    req.setDurationSeconds(durationSeconds);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->BanUser(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// StreamD: Social
// =========================================================================

void WingOutController::shoutout(const QString &platformId, const QString &targetUserName,
                                   QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::ShoutoutRequest req;
    req.setPlatformId(platformId);
    req.setTargetUserName(targetUserName);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->Shoutout(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::raidTo(const QString &platformId, const QString &targetChannel,
                                  QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RaidToRequest req;
    req.setPlatformId(platformId);
    req.setTargetChannel(targetChannel);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RaidTo(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getPeerIDs(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetPeerIDs(wingout::GetPeerIDsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetPeerIDsReply>()) {
            QVariantList list;
            for (const auto &pid : resp->peerIds()) {
                list.append(pid);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// StreamD: AI
// =========================================================================

void WingOutController::llmGenerate(const QString &prompt, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::LLMGenerateRequest req;
    req.setPrompt(prompt);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->LLMGenerate(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::LLMGenerateReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(resp->text())});
        }
    });
}

// =========================================================================
// StreamD: System
// =========================================================================

void WingOutController::restart(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->Restart(wingout::RestartRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::reinitStreamControllers(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->EXPERIMENTAL_ReinitStreamControllers(wingout::ReinitStreamControllersRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - Logging
// =========================================================================

void WingOutController::ffSetLoggingLevel(int level, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::FFSetLoggingLevelRequest req;
    req.setLevel(static_cast<wingout::LoggingLevelGadget::LoggingLevel>(level));
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->FFSetLoggingLevel(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - Output
// =========================================================================

void WingOutController::removeOutput(const QString &outputId, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::RemoveOutputRequest req;
    req.setOutputId(outputId);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->RemoveOutput(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getCurrentOutput(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetCurrentOutput(wingout::GetCurrentOutputRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetCurrentOutputReply>()) {
            QVariantMap result;
            result[QStringLiteral("outputId")] = resp->output().outputId();
            result[QStringLiteral("senderType")] = resp->output().senderType();
            // props is a map<string,string>; convert to QVariantMap
            QVariantMap props;
            for (auto it = resp->output().props().begin(); it != resp->output().props().end(); ++it) {
                props[it.key()] = it.value();
            }
            result[QStringLiteral("props")] = props;
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::switchOutputByProps(const QVariantMap &props,
                                              QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SwitchOutputByPropsRequest req;
    QHash<QString, QString> propsMap;
    for (auto it = props.begin(); it != props.end(); ++it) {
        propsMap[it.key()] = it.value().toString();
    }
    req.setProps(propsMap);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SwitchOutputByProps(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - SRT
// =========================================================================

void WingOutController::getOutputSRTStats(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetOutputSRTStats(wingout::GetOutputSRTStatsRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetOutputSRTStatsReply>()) {
            QVariantMap result;
            const auto &s = resp->stats();
            result[QStringLiteral("pktSent")] = static_cast<qint64>(s.pktSent());
            result[QStringLiteral("pktReceived")] = static_cast<qint64>(s.pktReceived());
            result[QStringLiteral("pktSendLoss")] = static_cast<qint64>(s.pktSendLoss());
            result[QStringLiteral("pktRecvLoss")] = static_cast<qint64>(s.pktRecvLoss());
            result[QStringLiteral("pktRetrans")] = static_cast<qint64>(s.pktRetrans());
            result[QStringLiteral("pktSendDrop")] = static_cast<qint64>(s.pktSendDrop());
            result[QStringLiteral("pktRecvDrop")] = static_cast<qint64>(s.pktRecvDrop());
            result[QStringLiteral("rttMs")] = s.rttMs();
            result[QStringLiteral("bandwidthMbps")] = s.bandwidthMbps();
            result[QStringLiteral("sendRateMbps")] = s.sendRateMbps();
            result[QStringLiteral("recvRateMbps")] = s.recvRateMbps();
            result[QStringLiteral("pktFlightSize")] = static_cast<qint64>(s.pktFlightSize());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::getSRTFlagInt(int flag, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::GetSRTFlagIntRequest req;
    req.setFlag(static_cast<wingout::SRTFlagIntGadget::SRTFlagInt>(flag));
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetSRTFlagInt(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetSRTFlagIntReply>()) {
            if (cb.isCallable())
                cb.call(QJSValueList{QJSValue(static_cast<double>(resp->value()))});
        }
    });
}

void WingOutController::setSRTFlagInt(int flag, qint64 value, QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetSRTFlagIntRequest req;
    req.setFlag(static_cast<wingout::SRTFlagIntGadget::SRTFlagInt>(flag));
    req.setValue(value);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetSRTFlagInt(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - End
// =========================================================================

void WingOutController::ffEnd(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->FFEnd(wingout::FFEndRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - Pipelines
// =========================================================================

void WingOutController::getPipelines(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetPipelines(wingout::GetPipelinesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetPipelinesReply>()) {
            QVariantList list;
            for (const auto &pipeline : resp->pipelines()) {
                QVariantMap item;
                item[QStringLiteral("id")] = pipeline.id_proto();
                item[QStringLiteral("description")] = pipeline.description();
                QVariantList nodes;
                for (const auto &node : pipeline.nodes()) {
                    QVariantMap n;
                    n[QStringLiteral("id")] = node.id_proto();
                    n[QStringLiteral("type")] = node.type();
                    n[QStringLiteral("description")] = node.description();
                    nodes.append(n);
                }
                item[QStringLiteral("nodes")] = nodes;
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// FFStream: Extended - Auto BitRate
// =========================================================================

void WingOutController::getVideoAutoBitRateConfig(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetVideoAutoBitRateConfig(wingout::GetVideoAutoBitRateConfigRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetVideoAutoBitRateConfigReply>()) {
            QVariantMap result;
            result[QStringLiteral("minBitrate")] = static_cast<qint64>(resp->config().minBitrate());
            result[QStringLiteral("maxBitrate")] = static_cast<qint64>(resp->config().maxBitrate());
            result[QStringLiteral("targetFps")] = resp->config().targetFps();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::setVideoAutoBitRateConfig(quint64 minBitrate, quint64 maxBitrate,
                                                    double targetFps,
                                                    QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetVideoAutoBitRateConfigRequest req;
    wingout::AutoBitRateVideoConfigProto config;
    config.setMinBitrate(minBitrate);
    config.setMaxBitrate(maxBitrate);
    config.setTargetFps(targetFps);
    req.setConfig(config);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetVideoAutoBitRateConfig(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getVideoAutoBitRateCalculator(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetVideoAutoBitRateCalculator(wingout::GetVideoAutoBitRateCalculatorRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetVideoAutoBitRateCalculatorReply>()) {
            QVariantMap result;
            result[QStringLiteral("type")] = resp->calculator().type();
            result[QStringLiteral("config")] = resp->calculator().config();
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::setVideoAutoBitRateCalculator(const QString &type, const QByteArray &config,
                                                        QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetVideoAutoBitRateCalculatorRequest req;
    wingout::AutoBitRateCalculatorProto calculator;
    calculator.setType(type);
    calculator.setConfig(config);
    req.setCalculator(calculator);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetVideoAutoBitRateCalculator(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// FFStream: Extended - Inputs
// =========================================================================

void WingOutController::getInputsInfo(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetInputsInfo(wingout::GetInputsInfoRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetInputsInfoReply>()) {
            QVariantList list;
            for (const auto &input : resp->inputs()) {
                QVariantMap item;
                item[QStringLiteral("id")] = input.id_proto();
                item[QStringLiteral("priority")] = input.priority();
                item[QStringLiteral("url")] = input.url();
                item[QStringLiteral("isActive")] = input.isActive();
                item[QStringLiteral("isSuppressed")] = input.isSuppressed();
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

void WingOutController::setInputCustomOption(const QString &inputId, const QString &key,
                                               const QString &value,
                                               QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetInputCustomOptionRequest req;
    req.setInputId(inputId);
    wingout::CustomOptionProto option;
    option.setKey(key);
    option.setValue(value);
    req.setOption(option);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetInputCustomOption(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::setStopInput(const QString &inputId, bool stop,
                                       QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetStopInputRequest req;
    req.setInputId(inputId);
    req.setStop(stop);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetStopInput(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// Channel Quality
// =========================================================================

void WingOutController::setChannelQuality(const QVariantList &channels,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::SetChannelQualityRequest req;
    QList<wingout::ChannelQualityEntry> entries;
    for (const auto &ch : channels) {
        auto map = ch.toMap();
        wingout::ChannelQualityEntry entry;
        entry.setLabel(map[QStringLiteral("label")].toString());
        entry.setQuality(map[QStringLiteral("quality")].toInt());
        entries.append(entry);
    }
    req.setChannels(entries);

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->SetChannelQuality(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::getChannelQuality(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->GetChannelQuality(wingout::GetChannelQualityRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::GetChannelQualityReply>()) {
            QVariantList list;
            for (const auto &entry : resp->channels()) {
                QVariantMap item;
                item[QStringLiteral("label")] = entry.label();
                item[QStringLiteral("quality")] = static_cast<int>(entry.quality());
                list.append(item);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(list)});
        }
    });
}

// =========================================================================
// AVD Management
// =========================================================================

void WingOutController::avdListRoutes(QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AVDListRoutes(wingout::AVDListRoutesRequest{}));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AVDListRoutesReply>()) {
            QVariantList routesList;
            for (const auto &route : resp->routes()) {
                QVariantMap routeMap;
                routeMap[QStringLiteral("path")] = route.path();
                routeMap[QStringLiteral("description")] = route.description();
                routeMap[QStringLiteral("isServing")] = route.isServing();

                QVariantList fwdList;
                for (const auto &fwd : route.forwardings()) {
                    QVariantMap fwdMap;
                    fwdMap[QStringLiteral("index")] = static_cast<int>(fwd.index());
                    fwdMap[QStringLiteral("hasPrivacyBlur")] = fwd.hasPrivacyBlur();
                    fwdMap[QStringLiteral("hasDeblemish")] = fwd.hasDeblemish();
                    fwdList.append(fwdMap);
                }
                routeMap[QStringLiteral("forwardings")] = fwdList;
                routesList.append(routeMap);
            }
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(routesList)});
        }
    });
}

void WingOutController::avdGetPrivacyBlur(const QString &routePath, qint32 forwardingIndex,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AVDGetPrivacyBlurRequest req;
    req.setRoutePath(routePath);
    req.setForwardingIndex(forwardingIndex);

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AVDGetPrivacyBlur(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AVDGetPrivacyBlurReply>()) {
            QVariantMap result;
            result[QStringLiteral("enabled")] = resp->enabled();
            result[QStringLiteral("blurRadius")] = resp->blurRadius();
            result[QStringLiteral("pixelateBlockSize")] = static_cast<qint64>(resp->pixelateBlockSize());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::avdSetPrivacyBlur(const QString &routePath, qint32 forwardingIndex,
                                            const QVariantMap &params,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AVDSetPrivacyBlurRequest req;
    req.setRoutePath(routePath);
    req.setForwardingIndex(forwardingIndex);
    if (params.contains(QStringLiteral("enabled")))
        req.setEnabled(params[QStringLiteral("enabled")].toBool());
    if (params.contains(QStringLiteral("blurRadius")))
        req.setBlurRadius(params[QStringLiteral("blurRadius")].toDouble());
    if (params.contains(QStringLiteral("pixelateBlockSize")))
        req.setPixelateBlockSize(params[QStringLiteral("pixelateBlockSize")].toLongLong());

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AVDSetPrivacyBlur(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

void WingOutController::avdGetDeblemish(const QString &routePath, qint32 forwardingIndex,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AVDGetDeblemishRequest req;
    req.setRoutePath(routePath);
    req.setForwardingIndex(forwardingIndex);

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AVDGetDeblemish(req));
    GRPC_CONNECT_REPLY(reply, {
        if (auto resp = reply->read<wingout::AVDGetDeblemishReply>()) {
            QVariantMap result;
            result[QStringLiteral("enabled")] = resp->enabled();
            result[QStringLiteral("sigmaS")] = resp->sigmaS();
            result[QStringLiteral("sigmaR")] = resp->sigmaR();
            result[QStringLiteral("diameter")] = static_cast<qint64>(resp->diameter());
            if (cb.isCallable())
                cb.call(QJSValueList{qjsEngine(this)->toScriptValue(result)});
        }
    });
}

void WingOutController::avdSetDeblemish(const QString &routePath, qint32 forwardingIndex,
                                          const QVariantMap &params,
                                          QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::AVDSetDeblemishRequest req;
    req.setRoutePath(routePath);
    req.setForwardingIndex(forwardingIndex);
    if (params.contains(QStringLiteral("enabled")))
        req.setEnabled(params[QStringLiteral("enabled")].toBool());
    if (params.contains(QStringLiteral("sigmaS")))
        req.setSigmaS(params[QStringLiteral("sigmaS")].toDouble());
    if (params.contains(QStringLiteral("sigmaR")))
        req.setSigmaR(params[QStringLiteral("sigmaR")].toDouble());
    if (params.contains(QStringLiteral("diameter")))
        req.setDiameter(params[QStringLiteral("diameter")].toLongLong());

    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->AVDSetDeblemish(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// Diagnostics
// =========================================================================

void WingOutController::injectDiagnostics(const QVariantMap &diagnostics,
                                            QJSValue callback, QJSValue errorCallback)
{
    GRPC_CHECK_CLIENT();

    wingout::InjectDiagnosticsRequest req;
    wingout::DiagnosticsProto diag;
    // Set optional fields from the map if present
    if (diagnostics.contains(QStringLiteral("latencyPreSending")))
        diag.setLatencyPreSending(diagnostics[QStringLiteral("latencyPreSending")].toInt());
    if (diagnostics.contains(QStringLiteral("latencySending")))
        diag.setLatencySending(diagnostics[QStringLiteral("latencySending")].toInt());
    if (diagnostics.contains(QStringLiteral("fpsInput")))
        diag.setFpsInput(diagnostics[QStringLiteral("fpsInput")].toInt());
    if (diagnostics.contains(QStringLiteral("fpsOutput")))
        diag.setFpsOutput(diagnostics[QStringLiteral("fpsOutput")].toInt());
    if (diagnostics.contains(QStringLiteral("bitrateVideo")))
        diag.setBitrateVideo(diagnostics[QStringLiteral("bitrateVideo")].toLongLong());
    if (diagnostics.contains(QStringLiteral("playerLagMin")))
        diag.setPlayerLagMin(diagnostics[QStringLiteral("playerLagMin")].toInt());
    if (diagnostics.contains(QStringLiteral("playerLagMax")))
        diag.setPlayerLagMax(diagnostics[QStringLiteral("playerLagMax")].toInt());
    if (diagnostics.contains(QStringLiteral("pingRtt")))
        diag.setPingRtt(diagnostics[QStringLiteral("pingRtt")].toInt());
    if (diagnostics.contains(QStringLiteral("wifiSsid")))
        diag.setWifiSsid(diagnostics[QStringLiteral("wifiSsid")].toString());
    if (diagnostics.contains(QStringLiteral("wifiBssid")))
        diag.setWifiBssid(diagnostics[QStringLiteral("wifiBssid")].toString());
    if (diagnostics.contains(QStringLiteral("wifiRssi")))
        diag.setWifiRssi(diagnostics[QStringLiteral("wifiRssi")].toInt());
    if (diagnostics.contains(QStringLiteral("viewersYoutube")))
        diag.setViewersYoutube(diagnostics[QStringLiteral("viewersYoutube")].toInt());
    if (diagnostics.contains(QStringLiteral("viewersTwitch")))
        diag.setViewersTwitch(diagnostics[QStringLiteral("viewersTwitch")].toInt());
    if (diagnostics.contains(QStringLiteral("viewersKick")))
        diag.setViewersKick(diagnostics[QStringLiteral("viewersKick")].toInt());
    if (diagnostics.contains(QStringLiteral("signal")))
        diag.setSignal(diagnostics[QStringLiteral("signal")].toInt());
    if (diagnostics.contains(QStringLiteral("streamTime")))
        diag.setStreamTime(diagnostics[QStringLiteral("streamTime")].toInt());
    if (diagnostics.contains(QStringLiteral("cpuUtilization")))
        diag.setCpuUtilization(diagnostics[QStringLiteral("cpuUtilization")].toFloat());
    if (diagnostics.contains(QStringLiteral("memoryUtilization")))
        diag.setMemoryUtilization(diagnostics[QStringLiteral("memoryUtilization")].toFloat());
    if (diagnostics.contains(QStringLiteral("channels"))) {
        QtProtobuf::int32List chList;
        for (const auto &v : diagnostics[QStringLiteral("channels")].toList())
            chList.append(QtProtobuf::int32(v.toInt()));
        diag.setChannels(chList);
    }
    req.setDiagnostics(diag);
    auto reply = std::shared_ptr<QGrpcCallReply>(m_client->InjectDiagnostics(req));
    GRPC_CONNECT_REPLY(reply, {
        if (cb.isCallable())
            cb.call();
    });
}

// =========================================================================
// Server-Streaming Subscriptions
// =========================================================================

void WingOutController::subscribeToChatMessages()
{
    if (!m_client) return;

    if (m_chatStream) {
        m_chatStream->cancel();
        m_chatStream.reset();
    }

    wingout::SubscribeToChatMessagesRequest req;
    m_chatStream = m_client->SubscribeToChatMessages(req);

    connect(m_chatStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (auto msg = m_chatStream->read<wingout::ChatMessageProto>()) {
            QVariantMap result;
            result[QStringLiteral("messageId")] = msg->id_proto();
            result[QStringLiteral("platform")] = msg->platform();
            result[QStringLiteral("userName")] = msg->userName();
            result[QStringLiteral("text")] = msg->message();
            result[QStringLiteral("timestamp")] = static_cast<qint64>(msg->timestamp());

            if (msg->hasEvent()) {
                const auto &evt = msg->event();
                result[QStringLiteral("eventId")] = evt.id_proto();
                result[QStringLiteral("createdAtUnixNano")] = static_cast<qint64>(evt.createdAtUnixNano());
                result[QStringLiteral("eventType")] = static_cast<int>(evt.eventType());
                result[QStringLiteral("eventPlatform")] = static_cast<int>(evt.platform());

                if (evt.hasUser()) {
                    QVariantMap user;
                    user[QStringLiteral("id")] = evt.user().id_proto();
                    user[QStringLiteral("slug")] = evt.user().slug();
                    user[QStringLiteral("name")] = evt.user().name();
                    user[QStringLiteral("nameReadable")] = evt.user().nameReadable();
                    result[QStringLiteral("user")] = user;
                }

                if (evt.hasTargetUser()) {
                    QVariantMap targetUser;
                    targetUser[QStringLiteral("id")] = evt.targetUser().id_proto();
                    targetUser[QStringLiteral("slug")] = evt.targetUser().slug();
                    targetUser[QStringLiteral("name")] = evt.targetUser().name();
                    targetUser[QStringLiteral("nameReadable")] = evt.targetUser().nameReadable();
                    result[QStringLiteral("targetUser")] = targetUser;
                }

                if (evt.hasMessage()) {
                    QVariantMap content;
                    content[QStringLiteral("content")] = evt.message().content();
                    content[QStringLiteral("formatType")] = static_cast<int>(evt.message().formatType());
                    content[QStringLiteral("inReplyTo")] = evt.message().inReplyTo();
                    result[QStringLiteral("content")] = content;
                }

                if (evt.hasMoney()) {
                    QVariantMap money;
                    money[QStringLiteral("currency")] = static_cast<int>(evt.money().currency());
                    money[QStringLiteral("amount")] = evt.money().amount();
                    result[QStringLiteral("money")] = money;
                }
            }

            emit chatMessageReceived(result);
        }
    });

    connect(m_chatStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "Chat subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToConfigChanges()
{
    if (!m_client) return;

    if (m_configStream) {
        m_configStream->cancel();
        m_configStream.reset();
    }

    wingout::SubscribeToConfigChangesRequest req;
    m_configStream = m_client->SubscribeToConfigChanges(req);

    connect(m_configStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (auto msg = m_configStream->read<wingout::ConfigChangeEvent>()) {
            emit configChanged(msg->config());
        }
    });

    connect(m_configStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "Config subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamsChanges()
{
    if (!m_client) return;

    if (m_streamsStream) {
        m_streamsStream->cancel();
        m_streamsStream.reset();
    }

    wingout::SubscribeToStreamsChangesRequest req;
    m_streamsStream = m_client->SubscribeToStreamsChanges(req);

    connect(m_streamsStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_streamsStream->read<wingout::StreamChangeEvent>()) {
            emit streamsChanged();
        }
    });

    connect(m_streamsStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "Streams subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToOAuthRequests()
{
    if (!m_client) return;

    if (m_oauthStream) {
        m_oauthStream->cancel();
        m_oauthStream.reset();
    }

    wingout::SubscribeToOAuthRequestsRequest req;
    m_oauthStream = m_client->SubscribeToOAuthRequests(req);

    connect(m_oauthStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (auto msg = m_oauthStream->read<wingout::OAuthRequestEvent>()) {
            QVariantMap result;
            result[QStringLiteral("requestId")] = msg->requestId();
            result[QStringLiteral("authUrl")] = msg->authUrl();
            result[QStringLiteral("platformId")] = msg->platformId();
            emit oauthRequestReceived(result);
        }
    });

    connect(m_oauthStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "OAuth subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamServersChanges()
{
    if (!m_client) return;

    if (m_serversStream) {
        m_serversStream->cancel();
        m_serversStream.reset();
    }

    wingout::SubscribeToStreamServersChangesRequest req;
    m_serversStream = m_client->SubscribeToStreamServersChanges(req);

    connect(m_serversStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_serversStream->read<wingout::StreamServerChangeEvent>()) {
            emit streamServersChanged();
        }
    });

    connect(m_serversStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "StreamServers subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamSourcesChanges()
{
    if (!m_client) return;

    if (m_sourcesStream) {
        m_sourcesStream->cancel();
        m_sourcesStream.reset();
    }

    wingout::SubscribeToStreamSourcesChangesRequest req;
    m_sourcesStream = m_client->SubscribeToStreamSourcesChanges(req);

    connect(m_sourcesStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_sourcesStream->read<wingout::StreamSourceChangeEvent>()) {
            emit streamSourcesChanged();
        }
    });

    connect(m_sourcesStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "StreamSources subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamSinksChanges()
{
    if (!m_client) return;

    if (m_sinksStream) {
        m_sinksStream->cancel();
        m_sinksStream.reset();
    }

    wingout::SubscribeToStreamSinksChangesRequest req;
    m_sinksStream = m_client->SubscribeToStreamSinksChanges(req);

    connect(m_sinksStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_sinksStream->read<wingout::StreamSinkChangeEvent>()) {
            emit streamSinksChanged();
        }
    });

    connect(m_sinksStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "StreamSinks subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamForwardsChanges()
{
    if (!m_client) return;

    if (m_forwardsStream) {
        m_forwardsStream->cancel();
        m_forwardsStream.reset();
    }

    wingout::SubscribeToStreamForwardsChangesRequest req;
    m_forwardsStream = m_client->SubscribeToStreamForwardsChanges(req);

    connect(m_forwardsStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_forwardsStream->read<wingout::StreamForwardChangeEvent>()) {
            emit streamForwardsChanged();
        }
    });

    connect(m_forwardsStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "StreamForwards subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToStreamPlayersChanges()
{
    if (!m_client) return;

    if (m_playersStream) {
        m_playersStream->cancel();
        m_playersStream.reset();
    }

    wingout::SubscribeToStreamPlayersChangesRequest req;
    m_playersStream = m_client->SubscribeToStreamPlayersChanges(req);

    connect(m_playersStream.get(), &QGrpcServerStream::messageReceived, this, [this]() {
        if (m_playersStream->read<wingout::StreamPlayerChangeEvent>()) {
            emit streamPlayersChanged();
        }
    });

    connect(m_playersStream.get(), &QGrpcServerStream::finished, this,
        [this](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "StreamPlayers subscription ended:" << status.message();
            }
        });
}

void WingOutController::subscribeToVariable(const QString &key)
{
    if (!m_client) return;

    // Cancel existing stream for this key
    auto stdKey = key.toStdString();
    auto varIt = m_variableStreams.find(stdKey);
    if (varIt != m_variableStreams.end()) {
        if (varIt->second) varIt->second->cancel();
        m_variableStreams.erase(varIt);
    }

    wingout::SubscribeToVariableRequest req;
    req.setKey(key);
    auto stream = m_client->SubscribeToVariable(req);
    auto *rawPtr = stream.get();
    m_variableStreams[stdKey] = std::move(stream);

    connect(rawPtr, &QGrpcServerStream::messageReceived, this, [this, key, rawPtr]() {
        if (auto msg = rawPtr->read<wingout::VariableChangeEvent>()) {
            emit variableChanged(msg->key(), msg->value());
        }
    });

    connect(rawPtr, &QGrpcServerStream::finished, this,
        [this, key](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "Variable subscription ended for" << key << ":" << status.message();
            }
        });
}

void WingOutController::subscribeToPlayerEnd(const QString &playerId)
{
    if (!m_client) return;

    // Cancel existing stream for this player
    auto stdPlayerId = playerId.toStdString();
    auto endIt = m_playerEndStreams.find(stdPlayerId);
    if (endIt != m_playerEndStreams.end()) {
        if (endIt->second) endIt->second->cancel();
        m_playerEndStreams.erase(endIt);
    }

    wingout::StreamPlayerEndChanRequest req;
    req.setPlayerId(playerId);
    auto stream = m_client->StreamPlayerEndChan(req);
    auto *rawPtr = stream.get();
    m_playerEndStreams[stdPlayerId] = std::move(stream);

    connect(rawPtr, &QGrpcServerStream::messageReceived, this, [this, rawPtr]() {
        if (auto msg = rawPtr->read<wingout::StreamPlayerEndEvent>()) {
            emit streamPlayerEnded(msg->playerId());
        }
    });

    connect(rawPtr, &QGrpcServerStream::finished, this,
        [this, playerId](const QGrpcStatus &status) {
            if (!status.isOk()) {
                qDebug() << "PlayerEnd subscription ended for" << playerId << ":" << status.message();
            }
        });
}

void WingOutController::unsubscribeAll()
{
    auto cancelAndReset = [](std::unique_ptr<QGrpcServerStream> &stream) {
        if (stream) {
            stream->cancel();
            stream.reset();
        }
    };

    cancelAndReset(m_chatStream);
    cancelAndReset(m_configStream);
    cancelAndReset(m_streamsStream);
    cancelAndReset(m_oauthStream);
    cancelAndReset(m_serversStream);
    cancelAndReset(m_sourcesStream);
    cancelAndReset(m_sinksStream);
    cancelAndReset(m_forwardsStream);
    cancelAndReset(m_playersStream);

    for (auto &[k, v] : m_variableStreams) {
        if (v) v->cancel();
    }
    m_variableStreams.clear();

    for (auto &[k, v] : m_playerEndStreams) {
        if (v) v->cancel();
    }
    m_playerEndStreams.clear();
}

// =========================================================================
// Embedded Daemon
// =========================================================================

#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif

QString WingOutController::startEmbeddedDaemon(const QString &streamdAddr, const QString &ffstreamAddr)
{
#ifdef Q_OS_ANDROID
    QJniObject jStreamd = QJniObject::fromString(streamdAddr);
    QJniObject jFFStream = QJniObject::fromString(ffstreamAddr);
    QJniObject result = QJniObject::callStaticObjectMethod(
        "center/dx/wingout2/MainActivity",
        "startDaemon",
        "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
        jStreamd.object<jstring>(),
        jFFStream.object<jstring>());
    QString addr = result.toString();
    if (addr.isEmpty()) {
        emit errorOccurred(QStringLiteral("Failed to start embedded daemon"));
    } else {
        qDebug() << "Embedded daemon started at:" << addr;
    }
    return addr;
#else
    Q_UNUSED(streamdAddr);
    Q_UNUSED(ffstreamAddr);
    emit errorOccurred(QStringLiteral("Embedded daemon is only supported on Android"));
    return {};
#endif
}

void WingOutController::stopEmbeddedDaemon()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "center/dx/wingout2/MainActivity",
        "stopDaemon",
        "()V");
    qDebug() << "Embedded daemon stopped";
#else
    emit errorOccurred(QStringLiteral("Embedded daemon is only supported on Android"));
#endif
}

bool WingOutController::isEmbeddedDaemonRunning()
{
#ifdef Q_OS_ANDROID
    return QJniObject::callStaticMethod<jboolean>(
        "center/dx/wingout2/MainActivity",
        "isDaemonRunning",
        "()Z");
#else
    return false;
#endif
}

void WingOutController::setStopDaemonOnClose(bool stop)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "center/dx/wingout2/MainActivity",
        "setStopDaemonOnClose",
        "(Z)V",
        static_cast<jboolean>(stop));
    qDebug() << "setStopDaemonOnClose:" << stop;
#else
    Q_UNUSED(stop);
#endif
}

#undef GRPC_CONNECT_REPLY
#undef GRPC_CHECK_CLIENT
