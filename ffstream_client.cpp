
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
#include "ffstream_client.h"
#include "qmlffstream_client.grpc.qpb.h"

namespace FFStream {

Client::Client(QObject *parent) : ffstream_grpc::FFStream::QmlClient{parent} {
  QObject::connect(this, &QGrpcClientBase::channelChanged, this,
                   &Client::_onChannelChanged);
}

ffstream_grpc::FFStream::Client *Client::client() { return this; }

void Client::setServerUri(const QString &uri) {
  QMutexLocker locker(&this->locker);
  this->serverURI = QUrl(uri);
  this->_reconnectIfNeeded();
}

void Client::_onChannelChanged() {
  bool hasValidUri = this->serverURI.isValid() && !this->serverURI.host().isEmpty();
  if (hasValidUri) {
    qDebug() << "ffstreamClient: channel changed (cached): " << this->serverURI;
    return;
  }
  auto http2Channel = dynamic_cast<QGrpcHttp2Channel *>(this->channel().get());
  if (!http2Channel) {
    qDebug() << "ffstreamClient: channel changed but no http2 channel yet";
    return;
  }
  QUrl channelUri = http2Channel->hostUri();
  if (channelUri.isEmpty() || channelUri.host().isEmpty()) {
    qDebug() << "ffstreamClient: channel changed but hostUri is empty, waiting for QML to set it";
    return;
  }
  this->serverURI = channelUri;
  this->serverChannelOptions = http2Channel->channelOptions();
  if (this->serverURI.scheme() == "https") {
    QSslConfiguration sslConfig;
    sslConfig.setPeerVerifyMode(QSslSocket::PeerVerifyMode::VerifyNone);
    this->serverChannelOptions.setSslConfiguration(sslConfig);
  }
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
  qDebug() << "ffstreamClient channel changed: " << this->serverURI;
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

bool Client::isChannelReady() { return this->channel() != nullptr; }

void Client::_reconnectIfNeeded() {
  bool hasValidUri = this->serverURI.isValid() && !this->serverURI.host().isEmpty();
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
  if (this->serverURI.scheme() == "https") {
    QSslConfiguration sslConfig =
        this->serverChannelOptions.sslConfiguration().value_or(
            QSslConfiguration());
    sslConfig.setPeerVerifyMode(QSslSocket::PeerVerifyMode::VerifyNone);
    this->serverChannelOptions.setSslConfiguration(sslConfig);
  }
  this->attachChannel(std::make_shared<QGrpcHttp2Channel>(
      this->serverURI, this->serverChannelOptions));
}

void Client::getLatencies(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  // Limit the lock to channel reconciliation only. The async
  // GetLatencies() RPC dispatch must not run under the mutex —
  // every other wrapper in this file (getInputQuality, getStats,
  // injectSubtitles, ...) does the same: lock-free dispatch after
  // _reconnectIfNeeded(). Holding the mutex across the async call
  // serialises every QML caller and can deadlock with
  // _onChannelChanged / processGRPCError, which both also take it.
  {
    QMutexLocker locker(&this->locker);
    this->_reconnectIfNeeded();
  }
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

void Client::getFPSFraction(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetFPSFractionRequest arg{};
  this->GetFPSFraction(arg, finishCallback, errorCallback, options);
}

void Client::getBitRates(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetBitRatesRequest arg{};
  this->GetBitRates(arg, finishCallback, errorCallback, options);
}

void Client::getStats(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::GetStatsRequest arg{};
  this->GetStats(arg, finishCallback, errorCallback, options);
}

void Client::injectSubtitles(
    const QByteArray &data, quint64 durationNS, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::InjectSubtitlesRequest arg{};
  // The generated proto exposes `bytes data` (QByteArray). Pass through.
  arg.setData(data);
  arg.setDurationNs(durationNS);
  this->InjectSubtitles(arg, finishCallback, errorCallback, options);
}

void Client::addInput(
    quint64 priority, const QString &url, const QVariantList &customOptions,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();

  avpipeline::InputConfig cfg;
  QList<avpipeline::CustomOption> protoOpts;
  protoOpts.reserve(customOptions.size());
  for (const QVariant &v : customOptions) {
    const QVariantMap m = v.toMap();
    avpipeline::CustomOption co;
    co.setKey(m.value(QStringLiteral("key")).toString());
    co.setValue(m.value(QStringLiteral("value")).toString());
    if (co.key().isEmpty()) {
      qWarning() << "addInput: skipping custom option with empty key";
      continue;
    }
    protoOpts.append(co);
  }
  cfg.setCustomOptions(protoOpts);

  ffstream_grpc::AddInputRequest req{};
  req.setPriority(priority);
  req.setUrl(url);
  req.setInputConfig(cfg);

  this->AddInput(req, finishCallback, errorCallback, options);
}

void Client::removeInput(
    quint64 priority, quint64 num, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();

  ffstream_grpc::RemoveInputRequest req{};
  req.setPriority(priority);
  req.setNum(num);

  this->RemoveInput(req, finishCallback, errorCallback, options);
}

void Client::getInputsInfo(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();

  ffstream_grpc::GetInputsInfoRequest req{};

  this->GetInputsInfo(req, finishCallback, errorCallback, options);
}

void Client::end(
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();

  ffstream_grpc::EndRequest req{};

  this->End(req, finishCallback, errorCallback, options);
}

void Client::switchOutput(
    const QString &videoCodec, quint32 width, quint32 height,
    quint64 videoBitrate, const QString &audioCodec, quint32 audioSampleRate,
    quint64 audioBitrate, quint64 maxBitrate,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();

  ffstream_grpc::VideoCodecConfig video;
  video.setCodecName(videoCodec);
  video.setWidth(width);
  video.setHeight(height);
  video.setAverageBitRate(videoBitrate);

  ffstream_grpc::AudioCodecConfig audio;
  audio.setCodecName(audioCodec);
  audio.setSampleRate(audioSampleRate);
  audio.setAverageBitRate(audioBitrate);

  ffstream_grpc::TranscoderConfig config;
  config.setVideo(video);
  config.setAudio(audio);

  ffstream_grpc::SwitchOutputByPropsRequest req;
  req.setConfig(config);
  req.setMaxBitRate(maxBitrate);

  this->SwitchOutputByProps(req, finishCallback, errorCallback, options);
}

void Client::setOutputUrl(
    const QString &url, const QJSValue &finishCallback,
    const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::SetOutputURLRequest req{};
  req.setUrl(url);
  this->SetOutputURL(req, finishCallback, errorCallback, options);
}

void Client::injectDiagnostics(
    const wingout_diagnostics::Diagnostics &diagnostics, quint64 durationNS,
    const QJSValue &finishCallback, const QJSValue &errorCallback,
    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options) {
  this->_reconnectIfNeeded();
  ffstream_grpc::InjectSubtitlesRequest arg{};
  // Diagnostics are binary; encode as base64 and mark with a fixed
  // magic header so the receiver can distinguish a serialised
  // Diagnostics payload from a literal user-typed subtitle. The
  // header is intentionally non-printable (SOH bytes) to make
  // collisions with real subtitle text effectively impossible while
  // still keeping the field valid UTF-8 — see DiagnosticsMagic in
  // ffstream_client.h for the protocol contract.
  QProtobufSerializer serializer;
  QByteArray ser = diagnostics.serialize(&serializer);
  QByteArray payload =
      DiagnosticsMagic().toUtf8() + ser.toBase64();
  arg.setData(payload);
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
