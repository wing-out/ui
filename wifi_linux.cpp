#include <qglobal.h>

#if defined(Q_OS_LINUX) && !defined(Q_OS_ANDROID)
#include <QDebug>
#include <QProcess>
#include <QStringList>

#include "wifi.h"

struct CmdResult {
  int exitCode = -1;
  QString out;
  QString err;
  bool ok() const { return exitCode == 0; }
};

CmdResult runCommand(const QString &program, const QStringList &arguments,
                     int timeoutMs = 3000) {
  CmdResult r;
  QProcess p;
  p.start(program, arguments);
  if (!p.waitForFinished(timeoutMs)) {
    qWarning() << "runCommand timeout:" << program << arguments;
    p.kill();
    p.waitForFinished();
    r.exitCode = -1;
    return r;
  }
  r.exitCode = p.exitCode();
  r.out = QString::fromUtf8(p.readAllStandardOutput());
  r.err = QString::fromUtf8(p.readAllStandardError());
  if (!r.ok())
    qWarning() << "runCommand failed:" << program << arguments << "exit"
               << r.exitCode << "stderr:" << r.err.trimmed();
  return r;
}

QStringList wiFiDevices() {
  CmdResult r =
      runCommand("nmcli", {"-t", "--fields", "DEVICE,TYPE", "device"});
  if (!r.ok())
    return {};

  QStringList result;
  const auto lines = r.out.split('\n', Qt::SkipEmptyParts);
  for (const QString &line : lines) {
    const auto parts = line.split(':');
    if (parts.size() < 2)
      continue;
    const QString dev = parts[0].trimmed();
    const QString type = parts[1].trimmed();
    if (type == QLatin1String("wifi"))
      result << dev;
  }
  return result;
}

QStringList splitNmcliLine(const QString &line) {
  QStringList fields;
  QString current;
  bool escape = false;

  for (QChar c : line) {
    if (escape) {
      // Whatever was escaped – ':' or '\' – we keep literally
      current.append(c);
      escape = false;
    } else if (c == '\\') {
      escape = true;
    } else if (c == ':') {
      fields << current;
      current.clear();
    } else {
      current.append(c);
    }
  }
  fields << current;
  return fields;
}

// Helper: parse nmcli wifi list lines
// nmcli -t --fields IN-USE,SSID,BSSID,DEVICE,SIGNAL,FREQ dev wifi list
struct NmWiFiRow {
  bool inUse = false;
  QString ssid;
  QString bssid;
  QString device;
  int signalPercent = 0;
  int freqMhz = 0;
};

QVector<NmWiFiRow> listWiFiRows() {
  QVector<NmWiFiRow> rows;

  CmdResult r =
      runCommand("nmcli",
                 {"-t", "--fields", "IN-USE,SSID,BSSID,DEVICE,SIGNAL,FREQ",
                  "dev", "wifi", "list"},
                 5000);
  if (!r.ok())
    return rows;

  const auto lines = r.out.split('\n', Qt::SkipEmptyParts);
  for (const QString &line : lines) {
    QString trimmed = line.trimmed();
    if (trimmed.isEmpty())
      continue;

    const QStringList parts = splitNmcliLine(trimmed);
    if (parts.size() < 6)
      continue;

    NmWiFiRow row;
    row.inUse = parts[0].trimmed().startsWith('*');
    row.ssid = parts[1].trimmed();
    row.bssid = parts[2].trimmed();
    row.device = parts[3].trimmed();

    bool okSig = false;
    bool okFreq = false;
    row.signalPercent = parts[4].trimmed().toInt(&okSig);
    row.freqMhz = parts[5].trimmed().toInt(&okFreq);
    if (!okSig)
      row.signalPercent = 0;
    if (!okFreq)
      row.freqMhz = 0;

    rows.push_back(row);
  }
  return rows;
}

int currentRSSIDbm(const QString &iface) {
  if (iface.isEmpty())
    return 0;

  CmdResult r = runCommand("iw", {"dev", iface, "link"});
  if (!r.ok())
    return 0;

  const auto lines = r.out.split('\n', Qt::SkipEmptyParts);
  for (const QString &line : lines) {
    const QString trimmed = line.trimmed();
    if (!trimmed.startsWith("signal:"))
      continue;
    // Example: "signal:  -52 dBm"
    const auto parts = trimmed.split(' ', Qt::SkipEmptyParts);
    if (parts.size() >= 2) {
      bool ok = false;
      int value = parts[1].toInt(&ok);
      if (ok)
        return value; // dBm
    }
  }
  return 0;
}

void startWiFiScan() {
  // Let NetworkManager trigger a scan
  CmdResult r = runCommand("nmcli", {"device", "wifi", "rescan"});
  if (!r.ok())
    qWarning() << "startWiFiScan: nmcli rescan failed";
}

QVector<WiFiInfo> getWiFiScanResults() {
  QVector<WiFiInfo> out;

  QVector<NmWiFiRow> rows = listWiFiRows();
  out.reserve(rows.size());

  for (const NmWiFiRow &row : rows) {
    WiFiInfo item;
    item.ssid = row.ssid;
    item.bssid = row.bssid;
    item.signalPercent = row.signalPercent;
    item.frequency = row.freqMhz;
    out.push_back(item);
  }

  return out;
}

int connectToWiFiAP(const QString &ssid, const QString &bssid,
                    const QString &security, const QString &password) {
  Q_UNUSED(security); // NetworkManager infers security from AP; we just pass
                      // password.

  if (ssid.isEmpty()) {
    qWarning() << "connectToWiFiAP: SSID is empty";
    return -1;
  }

  QStringList args{"device", "wifi", "connect", ssid};

  if (!bssid.isEmpty()) {
    args << "bssid" << bssid;
  }

  if (!password.isEmpty()) {
    args << "password" << password;
  }

  CmdResult r = runCommand("nmcli", args, 15000);
  if (!r.ok()) {
    qWarning() << "connectToWiFiAP: nmcli failed for" << ssid;
    return -1;
  }

  return 1;
}

void disconnectRequestedWiFiAP(int requestId) {
  Q_UNUSED(requestId);

  QStringList devs = wiFiDevices();
  if (devs.isEmpty()) {
    qWarning() << "disconnectRequestedWifiAp(Linux): no Wi-Fi devices";
    return;
  }

  for (const QString &dev : devs) {
    CmdResult r = runCommand("nmcli", {"device", "disconnect", dev});
    if (!r.ok()) {
      qWarning() << "disconnectRequestedWifiAp(Linux): failed for" << dev;
    }
  }
}

void disconnectAllRequestedWiFiAPs() { disconnectRequestedWiFiAP(1); }

QString getHotspotConfigurationJSON() {
  return "{}";
}

void saveHotspotConfiguration(const QString &ssid, const QString &psk) {
}

bool isHotspotEnabled() {
  return false;
}

void setHotspotEnabled(bool enabled) {
}

bool isLocalHotspotEnabled() {
  return false;
}

void setLocalHotspotEnabled(bool enabled) {
}

QString getHotspotIPAddress() {
  return "";
}

QString getLocalOnlyHotspotInfoJSON() {
  return "{}";
}

WiFiInfo getCurrentWiFiConnection() {
  WiFiInfo result;

  QVector<NmWiFiRow> rows = listWiFiRows();
  for (const NmWiFiRow &row : rows) {
    if (!row.inUse)
      continue;

    // Try to get real dBm via `iw dev <iface> link`
    int rssiDbm = currentRSSIDbm(row.device);

    result.ssid = row.ssid;
    result.bssid = row.bssid;
    result.rssi = rssiDbm;
    result.signalPercent = row.signalPercent;
    result.frequency = row.freqMhz;
    break;
  }

  return result;
}
#endif