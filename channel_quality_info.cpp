
#include "channel_quality_info.h"

void QChannelQualityInfo::setFrom(const ChannelQualityInfo &info) {
  m_name = info.name;
  m_quality = info.quality;
}

QChannelQualityInfo::QChannelQualityInfo(QObject *parent) : QObject(parent) {}

QChannelQualityInfo::QChannelQualityInfo(const QString &name, int quality,
                                         QObject *parent)
    : QObject(parent), m_name(name), m_quality(quality) {}

QChannelQualityInfo::QChannelQualityInfo(const QChannelQualityInfo &other)
    : QObject(other.parent()), m_name(other.m_name),
      m_quality(other.m_quality) {}

QChannelQualityInfo &
QChannelQualityInfo::operator=(const QChannelQualityInfo &other) {
  if (this != &other) {
    m_name = other.m_name;
    m_quality = other.m_quality;
  }
  return *this;
}

QString QChannelQualityInfo::toJSON() const {
  return QString("{\"name\":\"%1\",\"quality\":%2}").arg(m_name).arg(m_quality);
}
