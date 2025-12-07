#include <QGuiApplication>
#include <QQmlApplicationEngine>
#ifdef Q_OS_ANDROID
#include <QtCore/private/qandroidextras_p.h>
#include "android_permissions_wifi.cpp"
#endif

static QtMessageHandler g_prevHandler = nullptr;

static void filteredQtHandler(QtMsgType type,
                              const QMessageLogContext &ctx,
                              const QString &msg)
{
    // Drop only the noisy connection-refused messages
    if (msg.contains("QAbstractSocket::ConnectionRefusedError")) {
        return; // swallow it
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
  QGuiApplication app(argc, argv);
  g_prevHandler = qInstallMessageHandler(filteredQtHandler);

#ifdef Q_OS_ANDROID
  androidEnsureWifiLocationPermission();
#endif

  QQmlApplicationEngine engine;
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
  engine.loadFromModule("WingOut", "Main");

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
