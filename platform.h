
#include <QObject>
#include <QTime>
#include <QtQml/qqmlengine.h>

class Platform : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(Platform)
public:
    Q_INVOKABLE void vibrate(uint64_t duration_ms);
};
