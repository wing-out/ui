#include <QGuiApplication>
#include <QQmlApplicationEngine>
#ifdef Q_OS_ANDROID
#include <QtCore/private/qandroidextras_p.h>
#endif

int app(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);

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
