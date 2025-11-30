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
  Q_INVOKABLE void processGRPCError(const QVariant &error);
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
  getBitRates(const QJSValue &finishCallback, const QJSValue &errorCallback,
              const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options);
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
