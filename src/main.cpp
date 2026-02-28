#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>
#include <QDebug>
#include <QFontDatabase>

#include "wingoutcontroller.h"
#include "platformcontroller.h"
#include "djicontroller.h"
#include "streamingsettingscontroller.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("WingOut"));
    app.setOrganizationDomain(QStringLiteral("wingout.app"));
    app.setApplicationName(QStringLiteral("WingOut"));

    QQuickStyle::setStyle(QStringLiteral("Material"));

    QFontDatabase::addApplicationFont(
        QStringLiteral(":/qt/qml/WingOut/resources/fonts/MaterialSymbolsOutlined.ttf"));

    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));

    auto *wingoutController = new WingOutController(&engine);
    auto *platformController = new PlatformController(&engine);
    auto *djiController = new DJIController(&engine);
    auto *streamingSettings = new StreamingSettingsController(&engine);

    engine.rootContext()->setContextProperty("backendController", wingoutController);
    engine.rootContext()->setContextProperty("platformInstance", platformController);
    engine.rootContext()->setContextProperty("djiInstance", djiController);
    engine.rootContext()->setContextProperty("streamingSettingsInstance", streamingSettings);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    const QUrl url(QStringLiteral("qrc:/qt/qml/WingOut/qml/Main.qml"));
    qDebug() << "Loading QML from:" << url;
    engine.load(url);

    if (engine.rootObjects().isEmpty()) {
        qCritical() << "Failed to create root objects from" << url;
        return -1;
    }

    qDebug() << "QML loaded successfully with" << engine.rootObjects().size() << "root objects";
    return app.exec();
}
