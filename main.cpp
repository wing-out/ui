#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QLoggingCategory>
#include <cstdio>
#include "platform.h"
#ifdef Q_OS_ANDROID
#include "android_permissions.cpp"
#include <QtCore/private/qandroidextras_p.h>
#endif

static QtMessageHandler g_prevHandler = nullptr;

static void filteredQtHandler(QtMsgType type, const QMessageLogContext &ctx,
                              const QString &msg) {
  if (msg.contains("QAbstractSocket::ConnectionRefusedError")) {
    return;
  }
  if (msg.contains("Could not open media")) {
    return;
  }

  // Forward everything else to the previous handler (or stderr)
  if (g_prevHandler) {
    g_prevHandler(type, ctx, msg);
  } else {
    QByteArray local = msg.toLocal8Bit();
    std::fprintf(stderr, "%s\n", local.constData());
  }
}

int app(int argc, char *argv[]) {
  qDebug() << "Main: Starting app";
  QGuiApplication::setOrganizationName("WingOut");
  QGuiApplication::setOrganizationDomain("wingout.app");
  QGuiApplication::setApplicationName("WingOut");
  QGuiApplication app(argc, argv);
  QString loggingRules = QString::fromLocal8Bit(qgetenv("QT_LOGGING_RULES"));
  if (!loggingRules.isEmpty()) {
    loggingRules.append('\n');
  }
  loggingRules.append(QStringLiteral("qt.core.qfuture.continuations=false"));
  QLoggingCategory::setFilterRules(loggingRules);
  g_prevHandler = qInstallMessageHandler(filteredQtHandler);

#ifdef Q_OS_ANDROID
  androidEnsureWifiLocationPermission();
  androidEnsureBluetoothPermission();
  androidEnsureNearbyDevicesPermission();
#endif

  QQmlApplicationEngine engine;
  Platform *platformInstance = new Platform(&engine);
  engine.rootContext()->setContextProperty("platformInstance", platformInstance);

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
  engine.loadFromModule("WingOut", "Application");

  return app.exec();
}

int main(int argc, char *argv[]) {
#ifdef Q_OS_ANDROID
  if (argc <= 1) {
    return app(argc, argv);
  }

  if (argc > 1 && strcmp(argv[1], "-service") == 0) {
    qDebug() << "Service starting with from the same .so file";
    QAndroidService app(argc, argv);
    return app.exec();
  }

  qWarning() << "Unrecognized command line argument";
  return -1;
#else
  return app(argc, argv);
#endif
}
