#ifndef FFSTREAM_CLIENT_H
#define FFSTREAM_CLIENT_H

#include <QAbstractGrpcChannel>
#include <QDateTime>
#include <QGrpcChannelOptions>
#include <QJSValue>
#include <QMutex>
#include <QMutexLocker>
#include <QObject>
#include <QQmlEngine>
#include <QUrl>
#include <qvariant.h>

#include "diagnostics.qpb.h"
#include "ffstream.qpb.h"
#include "ffstream_client.grpc.qpb.h"
#include "qmlffstream_client.grpc.qpb.h"

namespace FFStream {
class Client : public ffstream_grpc::FFStream::QmlClient {
  Q_OBJECT
  QML_ELEMENT
public:
  explicit Client(QObject *parent = nullptr);
  ffstream_grpc::FFStream::Client *client();
  Q_INVOKABLE void setServerUri(const QString &uri);
  Q_INVOKABLE void processGRPCError(const QVariant &error);
  Q_INVOKABLE bool isChannelReady();
  Q_INVOKABLE void
  getLatencies(const QJSValue &finishCallback, const QJSValue &errorCallback,
               const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  getInputQuality(const QJSValue &finishCallback, const QJSValue &errorCallback,
                  const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  getOutputQuality(const QJSValue &finishCallback,
                   const QJSValue &errorCallback,
                   const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  getFPSFraction(const QJSValue &finishCallback, const QJSValue &errorCallback,
                 const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  getBitRates(const QJSValue &finishCallback, const QJSValue &errorCallback,
              const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  getStats(const QJSValue &finishCallback, const QJSValue &errorCallback,
            const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  injectSubtitles(const QByteArray &data, quint64 durationNS,
                  const QJSValue &finishCallback, const QJSValue &errorCallback,
                  const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  addInput(quint64 priority, const QString &url,
           const QVariantList &customOptions,
           const QJSValue &finishCallback, const QJSValue &errorCallback,
           const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  removeInput(quint64 priority, quint64 num,
              const QJSValue &finishCallback, const QJSValue &errorCallback,
              const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  // getInputsInfo wraps the auto-generated GetInputsInfo RPC. QML
  // cannot construct a GetInputsInfoRequest from a `{}` literal — the
  // C++ binding rejects the conversion before the call dispatches —
  // so callers must invoke this wrapper instead. Mirrors addInput /
  // removeInput, which take primitives and build the proto in C++.
  Q_INVOKABLE void
  getInputsInfo(const QJSValue &finishCallback,
                const QJSValue &errorCallback,
                const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  end(const QJSValue &finishCallback, const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  switchOutput(const QString &videoCodec, quint32 width, quint32 height,
               quint64 videoBitrate, const QString &audioCodec,
               quint32 audioSampleRate, quint64 audioBitrate, quint64 maxBitrate,
               const QJSValue &finishCallback, const QJSValue &errorCallback,
               const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  setOutputUrl(const QString &url, const QJSValue &finishCallback,
               const QJSValue &errorCallback,
               const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  // injectDiagnostics piggy-backs a serialised wingout_diagnostics
  // protobuf onto the InjectSubtitles RPC. The wire format on the
  // gRPC `text` field is:
  //
  //     <DiagnosticsMagic()> + base64(Diagnostics.serialize())
  //
  // The magic header lets a receiver distinguish a diagnostics
  // payload from a literal subtitle a user might type. Any text
  // that does NOT start with DiagnosticsMagic() must be treated as
  // a regular subtitle. The header is fixed: changing it is a wire
  // break and requires bumping both producer and consumer.
  Q_INVOKABLE void
  injectDiagnostics(const wingout_diagnostics::Diagnostics &diagnostics,
                    quint64 durationNS, const QJSValue &finishCallback,
                    const QJSValue &errorCallback,
                    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
  Q_INVOKABLE void
  injectDiagnostics(const QVariantMap &diagnosticsMap, quint64 durationNS,
                    const QJSValue &finishCallback,
                    const QJSValue &errorCallback,
                    const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);

  // DiagnosticsMagic returns the fixed prefix prepended to a
  // base64-encoded Diagnostics protobuf when piggy-backing on the
  // InjectSubtitles RPC. SOH (0x01) bookends keep the marker out of
  // any plausible subtitle while remaining valid UTF-8.
  static QString DiagnosticsMagic() {
    return QStringLiteral("\x01WINGOUT-DIAG\x01:");
  }
signals:
private:
  void _onChannelChanged();
  void _reconnectIfNeeded();
  QMutex locker;
  QUrl serverURI;
  QGrpcChannelOptions serverChannelOptions;
  bool ignoreImages = false;
};
} // namespace FFStream

#endif // FFSTREAM_CLIENT_H
