#include <QtQuickTest>
#include <QQmlContext>
#include <QQmlEngine>
#include <QPointer>
#include <QSettings>
#include "mock_platform.h"

class TestSetup : public QObject {
  Q_OBJECT

public:
  TestSetup() {}

public slots:
  void applicationAvailable() {
    // Use a test-specific organisation so QSettings does not pollute the
    // real application's persistent storage.
    QCoreApplication::setOrganizationName("WingOutTest");
    QCoreApplication::setOrganizationDomain("test.wingout.app");
    QCoreApplication::setApplicationName("WingOutTest");

    // Wipe any stale settings from previous test runs.
    QSettings settings;
    settings.clear();
    settings.sync();
  }

  void qmlEngineAvailable(QQmlEngine *engine) {
    // Each QML test file gets its own engine – create a fresh mock for each.
    m_mockPlatform = new MockPlatform(engine);
    engine->rootContext()->setContextProperty("platformInstance",
                                              m_mockPlatform);

    // Add the build directory to the import path so that QML modules built
    // as shared libraries (Platform, ffstream_grpc, streamd, etc.) can be
    // resolved at runtime.
    engine->addImportPath(QStringLiteral(WINGOUT_BUILD_DIR));

    // Expose the source dir so test QML can build file:// paths when needed.
    engine->rootContext()->setContextProperty(
        "wingoutSourceDir", QStringLiteral(WINGOUT_SOURCE_DIR));
  }

  void cleanupTestCase() {
    // Wipe settings written during the test.
    QSettings settings;
    settings.clear();
    settings.sync();
  }

private:
  QPointer<MockPlatform> m_mockPlatform;
};

QUICK_TEST_MAIN_WITH_SETUP(WingOut, TestSetup)

#include "tst_wingout.moc"
