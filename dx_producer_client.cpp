#include <QBuffer>
#include <QGrpcServerStream>
#include <QImage>
#include <QJSValue>
#include <QObject>
#include <QProtobufMessage>
#include <QString>
#include <QThread>

#include "dx_producer_client.h"
#include "image.h"
#include "streamd.qpb.h"
#include "streamd_client.grpc.qpb.h"
#include <cassert>
#include <qlogging.h>

namespace DXProducer {

Client::Client(QObject *parent) : streamd::StreamD::QmlClient{parent} {}

streamd::StreamD::Client *Client::client() {
  QmlClient::Client *client;
  client = this;
  return client;
}

void Client::ping(const QString &payloadToReturn,
                  const QString &payloadToIgnore,
                  const uint32_t requestExtraPayload,
                  const QJSValue &finishCallback, const QJSValue &errorCallback,
                  const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::PingRequest arg{};
  arg.setPayloadToReturn(payloadToReturn);
  arg.setPayloadToIgnore(payloadToIgnore);
  arg.setRequestExtraPayloadSize(requestExtraPayload);
  if (this->client() == nullptr) {
    qWarning() << "this->client() == nullptr";
    return;
  }
  this->Ping(arg, finishCallback, errorCallback, options);
}

void Client::subscribeToChatMessages(
    const QDateTime &since, const uint64_t limit,
    const QJSValue &messageCallback, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::SubscribeToChatMessagesRequest arg{};
  arg.setSinceUNIXNano(since.toMSecsSinceEpoch() * 1000 * 1000);
  arg.setLimit(limit);
  this->SubscribeToChatMessages(arg, messageCallback, finishCallback,
                                errorCallback, options);
}

void Client::getStreamStatus(
    const QString platID, const bool noCache, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::GetStreamStatusRequest arg{};
  arg.setPlatID(platID);
  arg.setNoCache(noCache);
  this->GetStreamStatus(arg, callback, errorCallback, options);
}

void Client::getVariable(
    const QString &key, const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::GetVariableRequest arg{};
  arg.setKey(key);
  this->GetVariable(arg, callback, errorCallback, options);
}

void Client::getVariableHash(
    const QString &key, streamd::HashTypeGadget::HashType hashType,
    const QJSValue &callback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::GetVariableHashRequest arg{};
  arg.setKey(key);
  arg.setHashType(hashType);
  this->GetVariableHash(arg, callback, errorCallback, options);
}
void Client::setVariable(
    const QString &key, const QByteArray &value, const QJSValue &callback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::SetVariableRequest arg{};
  arg.setKey(key);
  arg.setValue(value);
  this->SetVariable(arg, callback, errorCallback, options);
}

void Client::subscribeToVariable(
    const QString &key, const QJSValue &messageCallback,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  streamd::SubscribeToVariableRequest arg;
  arg.setKey(key);
  this->SubscribeToVariable(arg, messageCallback, finishCallback, errorCallback,
                            options);
}

void Client::setIgnoreImages(const bool value) {
  qInfo() << "setIgnoreImages" << value;
  this->ignoreImages = value;
}

void Client::subscribeToImage(
    const QString &key, const QJSValue &messageCallback,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
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

} // namespace DXProducer
