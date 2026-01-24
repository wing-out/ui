
#include <QBuffer>
#include <QGrpcHttp2Channel>
#include <QGrpcServerStream>
#include <QGrpcStatus>
#include <QImage>
#include <QJSValue>
#include <QProtobufMessage>
#include <QProtobufSerializer>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QString>
#include <QThread>
#include <qlogging.h>

#include "cpp_extensions.h"
#include "diagnostics.qpb.h"
#include "ffstream.qpb.h"
#include "ffstream_client.grpc.qpb.h"
#include "qmlffstream_client.grpc.qpb.h"
#include "ffstream_client.h"

namespace FFStream {

Client::Client(QObject *parent) : ffstream_grpc::FFStream::QmlClient{parent} {
  QObject::connect(this, &QGrpcClientBase::channelChanged, this,
                   &Client::_onChannelChanged);
}

ffstream_grpc::FFStream::Client *Client::client() {
  return this;
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
  if (status.code() == QtGrpc::StatusCode::Unavailable) {
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
  if (this->channel() != nullptr) {
    return;
  }
  qWarning() << "re-creating the channel";
  defer[=] { qDebug() << "/re-creating the channel"; };
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
}

void Client::getLatencies(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  QMutexLocker locker(&this->locker);
  this->_reconnectIfNeeded();
  ffstream_grpc::GetLatenciesRequest arg{};
  this->GetLatencies(arg, finishCallback, errorCallback, options);
}

void Client::getInputQuality(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetInputQualityRequest arg{};
  this->GetInputQuality(arg, finishCallback, errorCallback, options);
}

void Client::getOutputQuality(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetOutputQualityRequest arg{};
  this->GetOutputQuality(arg, finishCallback, errorCallback, options);
}

void Client::getBitRates(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetBitRatesRequest arg{};
  this->GetBitRates(arg, finishCallback, errorCallback, options);
}

void Client::injectSubtitles(
    const QByteArray &data, quint64 durationNS, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::InjectSubtitlesRequest arg{};
  QByteArray prefixedData;
  prefixedData.append((char)0x00); // Type 0: Plain text
  prefixedData.append(data);
  arg.setData(prefixedData);
  arg.setDurationNs(durationNS);
  this->InjectSubtitles(arg, finishCallback, errorCallback, options);
}

void Client::injectDiagnostics(
    const wingout_diagnostics::Diagnostics &diagnostics, quint64 durationNS,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::InjectSubtitlesRequest arg{};
  QByteArray prefixedData;
  prefixedData.append((char)0x01); // Type 1: Protobuf Diagnostics
  QProtobufSerializer serializer;
  prefixedData.append(diagnostics.serialize(&serializer));
  arg.setData(prefixedData);
  arg.setDurationNs(durationNS);
  this->InjectSubtitles(arg, finishCallback, errorCallback, options);
}

} // namespace FFStream
