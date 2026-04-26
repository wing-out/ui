#include <QBuffer>
#include <QGrpcHttp2Channel>
#include <QGrpcServerStream>
#include <QGrpcStatus>
#include <QImage>
#include <QJSValue>
#include <QObject>
#include <QProtobufMessage>
#include <QSslConfiguration>
#include <QSslSocket>
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

void Client::setServerUri(const QString &uri) {
  QMutexLocker locker(&this->locker);
  this->serverURI = QUrl(uri);
  this->_reconnectIfNeeded();
}

void Client::_onChannelChanged() {
  bool hasValidUri =
      this->serverURI.isValid() && !this->serverURI.host().isEmpty();
  if (hasValidUri) {
    qDebug() << "dxProducerClient: channel changed (cached): "
             << this->serverURI;
    return;
  }
  auto http2Channel = dynamic_cast<QGrpcHttp2Channel *>(this->channel().get());
  if (!http2Channel) {
    qDebug() << "dxProducerClient: channel changed but no http2 channel yet";
    return;
  }
  QUrl channelUri = http2Channel->hostUri();
  if (channelUri.isEmpty() || channelUri.host().isEmpty()) {
    qDebug() << "dxProducerClient: channel changed but hostUri is empty, "
                "waiting for QML to set it";
    return;
  }
  this->serverURI = channelUri;
  this->serverChannelOptions = http2Channel->channelOptions();
  QSslConfiguration sslConfig;
  sslConfig.setPeerVerifyMode(QSslSocket::PeerVerifyMode::VerifyNone);
  this->serverChannelOptions.setSslConfiguration(sslConfig);
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
  qDebug() << "dxProducerClient: channel changed: " << this->serverURI;
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
  if (status.code() == QtGrpc::StatusCode::Unavailable) {
    qDebug() << "processGRPCError(" << this->objectName()
             << ") attempting reconnect after Unavailable";
    QMutexLocker locker(&this->locker);
    this->_reconnectIfNeeded();
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

bool Client::isChannelReady() {
  return this->channel() != nullptr;
}

void Client::_reconnectIfNeeded() {
  bool hasValidUri =
      this->serverURI.isValid() && !this->serverURI.host().isEmpty();
  if (!hasValidUri) {
    qWarning() << "re-creating the channel skipped, server URI is not set";
    return;
  }

  bool needsReconnect = (this->channel() == nullptr);
  if (!needsReconnect) {
    auto http2Channel =
        dynamic_cast<QGrpcHttp2Channel *>(this->channel().get());
    if (!http2Channel) {
      needsReconnect = true;
    } else {
      QUrl channelUri = http2Channel->hostUri();
      if (!channelUri.isValid() || channelUri.host().isEmpty()) {
        needsReconnect = true;
      } else if (channelUri.scheme() != this->serverURI.scheme() ||
                 channelUri.host() != this->serverURI.host() ||
                 channelUri.port() != this->serverURI.port()) {
        needsReconnect = true;
      }
    }
  }

  if (!needsReconnect) {
    return;
  }

  qWarning() << "re-creating the channel" << this->serverURI;
  defer[=] { qDebug() << "/re-creating the channel"; };
  QSslConfiguration sslConfig =
      this->serverChannelOptions.sslConfiguration().value_or(
          QSslConfiguration());
  sslConfig.setPeerVerifyMode(QSslSocket::PeerVerifyMode::VerifyNone);
  this->serverChannelOptions.setSslConfiguration(sslConfig);
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
}

void Client::ping(const QString &payloadToReturn,
                  const QString &payloadToIgnore,
                  const uint32_t requestExtraPayload,
                  const QJSValue &finishCallback, const QJSValue &errorCallback,
                  const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);

  qDebug() << "dx_producer_client::ping - called, channel:" << (this->channel() != nullptr);

  // Try to reconnect first
  this->_reconnectIfNeeded();

  if (this->channel() == nullptr) {
    qDebug() << "dx_producer_client::ping - channel is null, returning early";
    return;
  }

  qDebug() << "dx_producer_client::ping - sending ping request";
  streamd::PingRequest arg{};
  arg.setPayloadToReturn(payloadToReturn);
  arg.setPayloadToIgnore(payloadToIgnore);
  arg.setRequestExtraPayloadSize(requestExtraPayload);
  this->Ping(arg, finishCallback, errorCallback, options);
}

void Client::getPlayerLag(
    const QString &streamSourceID, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::StreamPlayerGetLagRequest arg{};
  // streamSourceID is the proto field name, but its semantic value
  // is the registered stream player's streamID.
  arg.setStreamSourceID(streamSourceID);
  arg.setRequestUnixNano(QDateTime::currentDateTimeUtc().toMSecsSinceEpoch() * 1000 * 1000);
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

  if (this->chatStream) {
    qDebug() << "Cancelling previous chat stream";
    this->chatStream->cancel();
    delete this->chatStream;
    this->chatStream = nullptr;
  }

  streamd::SubscribeToChatMessagesRequest arg{};
  arg.setSinceUNIXNano(since.toMSecsSinceEpoch() * 1000 * 1000);
  arg.setLimit(limit);
  QJSEngine *jsEngine = qjsEngine(this);
  if (jsEngine == nullptr) {
    qWarning() << "Unable to call subscribeToChatMessages, it's only "
                  "callable from JS engine context";
    return;
  }

  this->chatStream =
      this->client()
          ->SubscribeToChatMessages(arg, options ? options->options()
                                                 : QGrpcCallOptions{})
          .release();

  auto messageReceivedFunc = [=]() mutable {
    if (!this->chatStream)
      return;
    auto message = this->chatStream->read<streamd::ChatMessage>();
    if (!message) {
      return;
    }
    QJSValueList argsOut;
    argsOut << jsEngine->toScriptValue(*message);
    messageCallback.call(argsOut);
  };

  auto finishedFunc = [=](const QGrpcStatus &status) mutable {
    if (!this->chatStream)
      return;
    this->chatStream->deleteLater();
    this->chatStream = nullptr;
    if (status.code() == QtGrpc::StatusCode::Ok) {
      finishCallback.call();
      return;
    }
    QJSValueList argsOut;
    argsOut << jsEngine->toScriptValue(status);
    errorCallback.call(argsOut);
  };

  QObject::connect(this->chatStream, &QGrpcServerStream::messageReceived, this,
                   messageReceivedFunc);

  QObject::connect(this->chatStream, &QGrpcServerStream::finished, this,
                   finishedFunc);
}

void Client::getStreamStatus(
    const QString platID, const bool noCache, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetStreamStatusRequest arg{};
  arg.setPlatID(platID);
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

void Client::banUser(
    const QString &platID, const QString &userID, const QString &reason,
    const qint64 deadlineUnixMs, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::BanUserRequest arg{};
  arg.setPlatID(platID);
  arg.setUserID(userID);
  arg.setReason(reason);
  if (deadlineUnixMs > 0) {
    arg.setDeadlineUnixNano(deadlineUnixMs * 1000000LL);
  }
  this->BanUser(arg, callback, errorCallback, options);
}

void Client::removeChatMessage(
    const QString &platID, const QString &messageID,
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::RemoveChatMessageRequest arg{};
  arg.setPlatID(platID);
  arg.setMessageID(messageID);
  this->RemoveChatMessage(arg, callback, errorCallback, options);
}

void Client::getBackendInfo(
    const QString &platID, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetBackendInfoRequest arg{};
  arg.setPlatID(platID);
  arg.setIncludeData(false);
  this->GetBackendInfo(arg, callback, errorCallback, options);
}

void Client::shoutout(
    const QString &platID, const QString &userID, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ShoutoutRequest arg{};
  arg.setPlatID(platID);
  arg.setUserID(userID);
  this->Shoutout(arg, callback, errorCallback, options);
}

void Client::raidTo(
    const QString &platID, const QString &userID, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::RaidToRequest arg{};
  arg.setPlatID(platID);
  arg.setUserID(userID);
  this->RaidTo(arg, callback, errorCallback, options);
}

void Client::llmGenerate(
    const QString &prompt, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::LLMGenerateRequest arg{};
  arg.setPrompt(prompt);
  this->LLMGenerate(arg, callback, errorCallback, options);
}

void Client::setTitle(
    const QString &platID, const QString &title, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SetTitleRequest arg{};
  arg.setPlatID(platID);
  arg.setTitle(title);
  this->SetTitle(arg, callback, errorCallback, options);
}

void Client::setIgnoreImages(const bool value) {
  QMutexLocker locker(&this->locker);
  // qInfo() << "setIgnoreImages" << value;
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

  if (this->imageStream) {
    qDebug() << "Cancelling previous image stream";
    this->imageStream->cancel();
    delete this->imageStream;
    this->imageStream = nullptr;
  }

  streamd::SubscribeToVariableRequest arg;
  arg.setKey("image/" + key);

  QJSEngine *jsEngine = qjsEngine(this);
  if (jsEngine == nullptr) {
    qWarning() << "Unable to call subscribeToImage, it's only "
                  "callable from JS engine context";
    return;
  }

  this->imageStream =
      this->client()
          ->SubscribeToVariable(arg, options ? options->options()
                                             : QGrpcCallOptions{})
          .release();

  auto messageReceivedFunc = [=]() mutable {
    if (!this->imageStream)
      return;
    auto message = this->imageStream->read<streamd::VariableChange>();
    if (ignoreImages || !message) {
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
    if (!this->imageStream)
      return;
    this->imageStream->deleteLater();
    this->imageStream = nullptr;
    if (status.code() == QtGrpc::StatusCode::Ok) {
      finishCallback.call();
      return;
    }
    QJSValueList argsOut;
    argsOut << QJSValue(status.message());
    errorCallback.call(argsOut);
  };

  QObject::connect(this->imageStream, &QGrpcServerStream::messageReceived, this,
                   messageReceivedFunc);

  QObject::connect(this->imageStream, &QGrpcServerStream::finished, this,
                   finishedFunc);
}

void Client::getConfig(const QJSValue &callback, const QJSValue &errorCallback,
                       const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::GetConfigRequest arg{};
  this->GetConfig(arg, callback, errorCallback, options);
}

void Client::setConfig(const QString &configYaml, const QJSValue &callback,
                       const QJSValue &errorCallback,
                       const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::SetConfigRequest arg{};
  arg.setConfig(configYaml);
  this->SetConfig(arg, callback, errorCallback, options);
}

void Client::startStream(
    const QString &platID, const QString &profileName, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::ApplyProfileRequest arg{};
  arg.setPlatID(platID);
  arg.setProfile(profileName);
  this->ApplyProfile(arg, callback, errorCallback, options);
}

void Client::endStream(const QString &platID, const QJSValue &callback,
                       const QJSValue &errorCallback,
                       const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::EndStreamRequest arg{};
  arg.setPlatID(platID);
  this->EndStream(arg, callback, errorCallback, options);
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
  Q_UNUSED(callback);
  Q_UNUSED(options);
  qWarning() << "DXProducerClient::listProfiles: ListProfilesRequest removed "
                "from streamd proto (commit 5e6b9dc); Profiles.qml will show "
                "empty list until RPC is restored.";
  QJSEngine *engine = qjsEngine(this);
  if (engine != nullptr && errorCallback.isCallable()) {
    QGrpcStatus status(QtGrpc::StatusCode::Unimplemented,
                       QStringLiteral("ListProfilesRequest removed from streamd "
                                      "proto in commit 5e6b9dc"));
    QJSValueList argsOut;
    argsOut << engine->toScriptValue(status);
    QJSValue errCb = errorCallback;
    errCb.call(argsOut);
  } else {
    qWarning() << "DXProducerClient::listProfiles: errorCallback could not be "
                  "delivered (engine null or callback not callable); caller "
                  "will not receive a response.";
  }
}

void Client::addStreamProfile(
    const QString &name, const QString &defaultTitle,
    const QString &defaultDescription, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  streamd::AddStreamProfileRequest arg{};
  arg.setName(name);
  arg.setDefaultTitle(defaultTitle);
  arg.setDefaultDescription(defaultDescription);
  this->AddStreamProfile(arg, callback, errorCallback, options);
}

void Client::listStreamSources(
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  Q_UNUSED(callback);
  Q_UNUSED(options);
  qWarning() << "DXProducerClient::listStreamSources: ListStreamSourcesRequest "
                "removed from streamd proto (commit 5e6b9dc); stream-source UI "
                "will show empty list until RPC is restored.";
  QJSEngine *engine = qjsEngine(this);
  if (engine != nullptr && errorCallback.isCallable()) {
    QGrpcStatus status(QtGrpc::StatusCode::Unimplemented,
                       QStringLiteral("ListStreamSourcesRequest removed from streamd "
                                      "proto in commit 5e6b9dc"));
    QJSValueList argsOut;
    argsOut << engine->toScriptValue(status);
    QJSValue errCb = errorCallback;
    errCb.call(argsOut);
  } else {
    qWarning() << "DXProducerClient::listStreamSources: errorCallback could not be "
                  "delivered (engine null or callback not callable); caller "
                  "will not receive a response.";
  }
}

} // namespace DXProducer
