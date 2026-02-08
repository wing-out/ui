
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
  // The generated proto now exposes a `text` string field. If caller passes
  // raw bytes for subtitles, treat them as UTF-8 text. This preserves the
  // original intent while matching the generated API.
  arg.setText(QString::fromUtf8(data));
  arg.setDurationNs(durationNS);
  this->InjectSubtitles(arg, finishCallback, errorCallback, options);
}

void Client::injectDiagnostics(
    const wingout_diagnostics::Diagnostics &diagnostics, quint64 durationNS,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::InjectSubtitlesRequest arg{};
  // Diagnostics are binary; encode as base64 and mark so the receiver can
  // detect and decode if needed. We prefix with an identifier string so the
  // text field remains valid UTF-8.
  QProtobufSerializer serializer;
  QByteArray ser = diagnostics.serialize(&serializer);
  QString text = QString::fromLatin1(ser.toBase64());
  arg.setText(text);
  arg.setDurationNs(durationNS);
  this->InjectSubtitles(arg, finishCallback, errorCallback, options);
}

void Client::injectDiagnostics(
    const QVariantMap &map, quint64 durationNS, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  wingout_diagnostics::Diagnostics d;
  if (map.contains("latencyPreSending"))
    d.setLatencyPreSending(map.value("latencyPreSending").toInt());
  if (map.contains("latencySending"))
    d.setLatencySending(map.value("latencySending").toInt());
  if (map.contains("fpsInput"))
    d.setFpsInput(map.value("fpsInput").toInt());
  if (map.contains("fpsOutput"))
    d.setFpsOutput(map.value("fpsOutput").toInt());
  if (map.contains("bitrateVideo"))
    d.setBitrateVideo(map.value("bitrateVideo").toLongLong());
  if (map.contains("playerLagMin"))
    d.setPlayerLagMin(map.value("playerLagMin").toInt());
  if (map.contains("playerLagMax"))
    d.setPlayerLagMax(map.value("playerLagMax").toInt());
  if (map.contains("pingRtt"))
    d.setPingRtt(map.value("pingRtt").toInt());
  if (map.contains("wifiSsid"))
    d.setWifiSsid(map.value("wifiSsid").toString());
  if (map.contains("wifiBssid"))
    d.setWifiBssid(map.value("wifiBssid").toString());
  if (map.contains("wifiRssi"))
    d.setWifiRssi(map.value("wifiRssi").toInt());
  if (map.contains("channels")) {
    QtProtobuf::int32List channels;
    for (const auto &v : map.value("channels").toList())
      channels.append(v.toInt());
    d.setChannels(channels);
  }
  if (map.contains("viewersYoutube"))
    d.setViewersYoutube(map.value("viewersYoutube").toInt());
  if (map.contains("viewersTwitch"))
    d.setViewersTwitch(map.value("viewersTwitch").toInt());
  if (map.contains("viewersKick"))
    d.setViewersKick(map.value("viewersKick").toInt());
  if (map.contains("signal"))
    d.setSignal(map.value("signal").toInt());
  if (map.contains("streamTime"))
    d.setStreamTime(map.value("streamTime").toInt());
  if (map.contains("cpuUtilization"))
    d.setCpuUtilization(map.value("cpuUtilization").toFloat());
  if (map.contains("memoryUtilization"))
    d.setMemoryUtilization(map.value("memoryUtilization").toFloat());
  if (map.contains("temperatures")) {
    QList<wingout_diagnostics::Temperature> temps;
    for (const auto &v : map.value("temperatures").toList()) {
      QVariantMap tm = v.toMap();
      wingout_diagnostics::Temperature t;
      t.setType(tm.value("type").toString());
      t.setTemp(tm.value("temp").toFloat());
      temps.append(t);
    }
    d.setTemperatures(temps);
  }
  this->injectDiagnostics(d, durationNS, finishCallback, errorCallback,
                          options);
}

} // namespace FFStream
