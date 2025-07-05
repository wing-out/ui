
#include <QObject>
#include <QTime>
#include <QtQml/qqmlengine.h>

class Platform : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_NAMED_ELEMENT(Platform)
  Q_PROPERTY(
      int signalStrength READ getSignalStrength WRITE setSignalStrength NOTIFY onSignalStrengthChanged)
public:
  explicit Platform(QObject* parent = nullptr) : QObject(parent), signalStrength(-1) {}
  Q_INVOKABLE void vibrate(uint64_t duration_ms, bool is_notification);
  Q_INVOKABLE void setEnableRunningInBackground(bool value);
  Q_INVOKABLE void startMonitoringSignalStrength();
  int getSignalStrength() {
    return signalStrength;
  }
  void setSignalStrength(int strength) {
    if (signalStrength != strength) {
      signalStrength = strength;
      emit onSignalStrengthChanged(strength);
    }
  }

signals:
  void onSignalStrengthChanged(int strength);

private:
  int signalStrength;
};
