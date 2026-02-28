#include <QtQuickTest/quicktest.h>
#include <QQmlEngine>
#include <QQmlContext>
#include "mock_platform.h"
#include "mock_backend.h"

class Setup : public QObject
{
    Q_OBJECT

public:
    Setup() {}

public slots:
    void qmlEngineAvailable(QQmlEngine *engine) {
        // Register mock platform as context property (matches main.cpp pattern)
        engine->rootContext()->setContextProperty(
            QStringLiteral("platformInstance"), &m_platform);

        // Register mock backend as context property for tests to use
        engine->rootContext()->setContextProperty(
            QStringLiteral("mockBackend"), &m_backend);

        // Add QML import path for WingOut module
        engine->addImportPath(QStringLiteral(":/qt/qml"));
        engine->addImportPath(QStringLiteral("qrc:/qt/qml"));
    }

private:
    MockPlatform m_platform;
    MockBackend m_backend;
};

QUICK_TEST_MAIN_WITH_SETUP(tst_wingout, Setup)

#include "tst_wingout.moc"
