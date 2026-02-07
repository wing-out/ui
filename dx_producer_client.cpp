#include <QBuffer>
#include <QGrpcHttp2Channel>
#include <QGrpcServerStream>
#include <QGrpcStatus>
#include <QImage>
#include <QJSValue>
#include <QObject>
#include <QProtobufMessage>
#include <QString>
#include <QThread>
#include <qlogging.h>

#include "cpp_extensions.h"
#include "dx_producer_client.h"
#include "image.h"
#include "streamd.qpb.h"
#include "streamd_client.grpc.qpb.h"
#include <cassert>

namespace DXProducer {

Client::Client(QObject *parent) : streamd::StreamD::QmlClient{parent} {
  QObject::connect(this, &QGrpcClientBase::channelChanged, this,
                   &Client::_onChannelChanged);
}

streamd::StreamD::Client *Client::client() {
  QmlClient::Client *client;
  client = this;
  return client;
}

void Client::_onChannelChanged() {
  if (!this->serverURI.isEmpty()) {
    return;
  }
  auto http2Channel = dynamic_cast<QGrpcHttp2Channel *>(this->channel().get());
  this->serverURI = http2Channel->hostUri();
  this->serverChannelOptions = http2Channel->channelOptions();
  QSslConfiguration sslConfig;
  sslConfig.setPeerVerifyMode(QSslSocket::PeerVerifyMode::VerifyNone);
  this->serverChannelOptions.setSslConfiguration(sslConfig);
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
  qDebug() << "channel changed: " << this->serverURI;
}

void Client::processGRPCError(const QVariant &error) {
  if (!error.canConvert<QGrpcStatus>()) {
    qDebug() << "processGRPCError(" << this->objectName() << "):" << error;
    return;
  }
  auto status = error.value<QGrpcStatus>();
  if (status.code() == QtGrpc::StatusCode::Cancelled) {
    return;
  }
  if (status.message().contains("unable to get audio position")) {
    return;
  }
  {
    qDebug() << "processGRPCError(" << this->objectName() << ")" << error;
    defer[=] { qDebug() << "/processGRPCError" << error; };
    if (status.code() != QtGrpc::StatusCode::Internal) {
      return;
    }
    qDebug() << "processGRPCError(): locking";
    QMutexLocker locker(&this->locker);
    qDebug() << "processGRPCError(): re-creating the channel";
    this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
        this->serverURI, this->serverChannelOptions));
  }
}

void Client::_reconnectIfNeeded() {
  auto channel = this->channel();
  if (this->channel() != nullptr) {
    return;
  }
  qWarning() << "re-creating the channel";
  defer[=] { qDebug() << "/re-creating the channel"; };
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
}

void Client::ping(const QString &payloadToReturn,
                  const QString &payloadToIgnore,
                  const uint32_t requestExtraPayload,
                  const QJSValue &finishCallback, const QJSValue &errorCallback,
                  const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::PingRequest arg{};
  arg.setPayloadToReturn(payloadToReturn);
  arg.setPayloadToIgnore(payloadToIgnore);
  arg.setRequestExtraPayloadSize(requestExtraPayload);
  this->Ping(arg, finishCallback, errorCallback, options);
}

void Client::getPlayerLag(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::StreamPlayerGetLagRequest arg{};
  arg.setStreamSourceID("pixel/dji-osmo-pocket-3");
  arg.setRequestUnixNano(QDateTime::currentDateTimeUtc().toMSecsSinceEpoch() *
                         1000 * 1000);
  this->StreamPlayerGetLag(arg, finishCallback, errorCallback, options);
}

void Client::subscribeToChatMessages(
    const QDateTime &since, const uint64_t limit,
    const QJSValue &messageCallback, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  qDebug() << "subscribeToChatMessages";
  defer[=] { qDebug() << "/subscribeToChatMessages"; };
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SubscribeToChatMessagesRequest arg{};
  arg.setSinceUNIXNano(since.toMSecsSinceEpoch() * 1000 * 1000);
  arg.setLimit(limit);
  streamd::ChatMessage a;
  this->SubscribeToChatMessages(arg, messageCallback, finishCallback,
                                errorCallback, options);
}

void Client::getStreamStatus(
    const QString platID, const bool noCache, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetStreamStatusRequest arg{};
  // Build fully-qualified stream id expected by the generated Qt protobuf API
  streamd::StreamIDFullyQualified id{};
  id.setPlatformID(platID);
  arg.setId_proto(id);
  arg.setNoCache(noCache);
  this->GetStreamStatus(arg, callback, errorCallback, options);
}

void Client::getVariable(
    const QString &key, const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetVariableRequest arg{};
  arg.setKey(key);
  this->GetVariable(arg, callback, errorCallback, options);
}

void Client::getVariableHash(
    const QString &key, streamd::HashTypeGadget::HashType hashType,
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  streamd::GetVariableHashRequest arg{};
  arg.setKey(key);
  arg.setHashType(hashType);
  this->GetVariableHash(arg, callback, errorCallback, options);
}
void Client::setVariable(
    const QString &key, const QByteArray &value, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SetVariableRequest arg{};
  arg.setKey(key);
  arg.setValue(value);
  this->SetVariable(arg, callback, errorCallback, options);
}

void Client::subscribeToVariable(
    const QString &key, const QJSValue &messageCallback,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  qDebug() << "subscribeToVariable" << key;
  defer[=] { qDebug() << "/subscribeToVariable" << key; };
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SubscribeToVariableRequest arg;
  arg.setKey(key);
  this->SubscribeToVariable(arg, messageCallback, finishCallback, errorCallback,
                            options);
}

void Client::setIgnoreImages(const bool value) {
  QMutexLocker locker(&this->locker);
  //qInfo() << "setIgnoreImages" << value;
  this->ignoreImages = value;
}

void Client::subscribeToImage(
    const QString &key, const QJSValue &messageCallback,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  qDebug() << "subscribeToImage" << key;
  defer[=] { qDebug() << "/subscribeToImage" << key; };
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SubscribeToVariableRequest arg;
  arg.setKey("image/" + key);

  QJSEngine *jsEngine = qjsEngine(this);
  if (jsEngine == nullptr) {
    qWarning() << "Unable to call subscribeToImage, it's only "
                  "callable from JS engine context";
    return;
  }

  auto stream = this->client()
                    ->SubscribeToVariable(arg, options ? options->options()
                                                       : QGrpcCallOptions{})
                    .release();

  auto messageReceivedFunc = [=]() mutable {
    auto message = stream->read<streamd::VariableChange>();
    if (ignoreImages) {
      return;
    }
    QByteArray webpData = message->value();
    QByteArray pngData = convertWebPtoPNG(webpData);
    QString base64 = QString::fromLatin1(pngData.toBase64());
    QString imageURI = "data:image/png;base64," + base64;
    QJSValueList argsOut;
    argsOut << QJSValue(imageURI);
    messageCallback.call(argsOut);
  };

  auto finishedFunc = [=](const QGrpcStatus &status) mutable {
    delete stream;
    if (status.code() == QtGrpc::StatusCode::Ok) {
      finishCallback.call();
      return;
    }
    QJSValueList argsOut;
    argsOut << QJSValue(status.message());
    errorCallback.call(argsOut);
  };

  QObject::connect(stream, &QGrpcServerStream::messageReceived, this,
                   messageReceivedFunc);

  QObject::connect(stream, &QGrpcServerStream::finished, this, finishedFunc);
}

void Client::getConfig(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetConfigRequest arg{};
  this->GetConfig(arg, callback, errorCallback, options);
}

void Client::setConfig(
    const QString &configYaml, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SetConfigRequest arg{};
  arg.setConfig(configYaml);
  this->SetConfig(arg, callback, errorCallback, options);
}

void Client::startStream(
    const QString &platID, const QString &profileName,
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  // Use ApplyProfile RPC (exists in current proto) to start a stream by profile
  streamd::ApplyProfileRequest arg{};
  streamd::StreamIDFullyQualified id{};
  id.setPlatformID(platID);
  arg.setId_proto(id);
  arg.setProfile(profileName);
  this->ApplyProfile(arg, callback, errorCallback, options);
}

void Client::endStream(
    const QString &platID, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  // Use SetStreamActive RPC to deactivate (end) a stream for the platform
  streamd::SetStreamActiveRequest arg{};
  streamd::StreamIDFullyQualified id{};
  id.setPlatformID(platID);
  arg.setId_proto(id);
  arg.setIsActive(false);
  this->SetStreamActive(arg, callback, errorCallback, options);
}

void Client::listStreamForwards(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ListStreamForwardsRequest arg{};
  this->ListStreamForwards(arg, callback, errorCallback, options);
}

void Client::listStreamServers(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ListStreamServersRequest arg{};
  this->ListStreamServers(arg, callback, errorCallback, options);
}

void Client::listStreamPlayers(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ListStreamPlayersRequest arg{};
  this->ListStreamPlayers(arg, callback, errorCallback, options);
}

void Client::listProfiles(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ListProfilesRequest arg{};
  this->ListProfiles(arg, callback, errorCallback, options);
}

void Client::listStreamSources(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ListStreamSourcesRequest arg{};
  this->ListStreamSources(arg, callback, errorCallback, options);
}

} // namespace DXProducer
