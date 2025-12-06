#pragma once

#include <QObject>
#include <QString>
#include <qtmetamacros.h>

struct ChannelQualityInfo {
  QString name;
  int quality = 0;
};

class QChannelQualityInfo : public QObject {
  Q_OBJECT
  Q_PROPERTY(QString name READ name CONSTANT)
  Q_PROPERTY(int quality READ quality CONSTANT)

public:
  explicit QChannelQualityInfo(QObject *parent = nullptr);
  QChannelQualityInfo(const ChannelQualityInfo &info, QObject *parent = nullptr);
  QChannelQualityInfo(const QString &name, int quality = 0, QObject *parent = nullptr);
  QChannelQualityInfo(const QChannelQualityInfo &other);
  QChannelQualityInfo &operator=(const QChannelQualityInfo &other);

  void setFrom(const ChannelQualityInfo &snapshot);

  QString name() const { return m_name; }
  int quality() const { return m_quality; }
  Q_INVOKABLE QString toJSON() const;

private:
  QString m_name;
  int m_quality = 0;
};
