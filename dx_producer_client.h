#ifndef DX_PRODUCER_CLIENT_H
#define DX_PRODUCER_CLIENT_H

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

#include "qmlstreamd_client.grpc.qpb.h"
#include "streamd.qpb.h"
#include "streamd_client.grpc.qpb.h"

namespace DXProducer {
class Client : public streamd::StreamD::QmlClient {
  Q_OBJECT
  QML_ELEMENT
public:
  explicit Client(QObject *parent = nullptr);
  streamd::StreamD::Client *client();
  Q_INVOKABLE void
  ping(const QString &payloadToReturn, const QString &payloadToIgnore,
       const uint32_t requestExtraPayload, const QJSValue &finishCallback,
       const QJSValue &errorCallback,
       const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void subscribeToChatMessages(
      const QDateTime &since, const uint64_t limit,
      const QJSValue &messageCallback, const QJSValue &finishCallback,
      const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void getStreamStatus(
      const QString platID, const bool noCache, const QJSValue &callback,
      const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void
  getVariable(const QString &key, const QJSValue &callback,
              const QJSValue &errorCallback,
              const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void getVariableHash(
      const QString &key, streamd::HashTypeGadget::HashType hashType,
      const QJSValue &callback, const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void
  setVariable(const QString &key, const QByteArray &value,
              const QJSValue &callback, const QJSValue &errorCallback,
              const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void subscribeToVariable(
      const QString &key, const QJSValue &messageCallback,
      const QJSValue &finishCallback, const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void subscribeToImage(
      const QString &key, const QJSValue &messageCallback,
      const QJSValue &finishCallback, const QJSValue &errorCallback,
      const QtGrpcQuickPrivate::QQmlGrpcCallOptions *options = nullptr);
  Q_INVOKABLE void setIgnoreImages(const bool value);
  Q_INVOKABLE void processGRPCError(const QVariant &error);
signals:
private:
  void _onChannelChanged();
  void _reconnectIfNeeded();
  QMutex locker;
  QUrl serverURI;
  QGrpcChannelOptions serverChannelOptions;
  bool ignoreImages = false;
};
} // namespace DXProducer

#endif // DX_PRODUCER_CLIENT_H
