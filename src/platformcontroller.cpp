#include "platformcontroller.h"
#include <QDebug>
#include <QFile>
#include <QDir>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <jni.h>

#define JAVA_WIFI_CLASS "center/dx/wingout2/WiFiHelper"
#define JAVA_VIBRATOR_CLASS "center/dx/wingout2/VibratorWrapper"
#define JAVA_SIGNAL_CLASS "center/dx/wingout2/SignalHelper"

static QJniObject getAndroidContext()
{
    return QJniObject(QNativeInterface::QAndroidApplication::context());
}
#else
#include <QProcess>
#endif

// Forward declaration of s_instance for JNI callback (Android only)
#ifdef Q_OS_ANDROID
static PlatformController *s_instance = nullptr;
#endif

PlatformController::PlatformController(QObject *parent)
    : QObject(parent)
{
#ifdef Q_OS_ANDROID
    s_instance = this;
#endif
}

PlatformController::~PlatformController()
{
#ifdef Q_OS_ANDROID
    if (s_instance == this)
        s_instance = nullptr;
#endif
}

float PlatformController::cpuUtilization() const { return m_cpuUtilization; }
float PlatformController::memoryUtilization() const { return m_memoryUtilization; }
QVariantList PlatformController::temperatures() const { return m_temperatures; }
int PlatformController::signalStrength() const { return m_signalStrength; }
bool PlatformController::isHotspotEnabled() const { return m_isHotspotEnabled; }

// ============================================================================
// updateResources
// ============================================================================

void PlatformController::updateResources()
{
    // CPU usage from /proc/stat (works on both Linux and Android)
    QFile statFile(QStringLiteral("/proc/stat"));
    if (statFile.open(QIODevice::ReadOnly)) {
        QString line = statFile.readLine();
        QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (parts.size() >= 8) {
            quint64 user = parts[1].toULongLong();
            quint64 nice = parts[2].toULongLong();
            quint64 system = parts[3].toULongLong();
            quint64 idle = parts[4].toULongLong();
            quint64 iowait = parts[5].toULongLong();
            quint64 total = user + nice + system + idle + iowait;
            quint64 busy = total - idle - iowait;

            if (m_prevCpuTotal > 0) {
                quint64 dTotal = total - m_prevCpuTotal;
                quint64 dBusy = busy - m_prevCpuBusy;
                float cpu = dTotal > 0
                    ? static_cast<float>(dBusy) / static_cast<float>(dTotal) * 100.0f
                    : 0.0f;
                if (cpu != m_cpuUtilization) {
                    m_cpuUtilization = cpu;
                    emit cpuUtilizationChanged();
                }
            }
            m_prevCpuTotal = total;
            m_prevCpuBusy = busy;
        }
    }

#ifdef Q_OS_ANDROID
    // Memory usage via ActivityManager on Android
    QJniObject activity = getAndroidContext();
    if (activity.isValid()) {
        QJniObject activityManager = activity.callObjectMethod(
            "getSystemService", "(Ljava/lang/String;)Ljava/lang/Object;",
            QJniObject::fromString(QStringLiteral("activity")).object());
        if (activityManager.isValid()) {
            QJniObject memInfo("android/app/ActivityManager$MemoryInfo");
            activityManager.callMethod<void>(
                "getMemoryInfo", "(Landroid/app/ActivityManager$MemoryInfo;)V",
                memInfo.object());
            jlong totalMem = memInfo.getField<jlong>("totalMem");
            jlong availMem = memInfo.getField<jlong>("availMem");
            if (totalMem > 0) {
                float mem = static_cast<float>(totalMem - availMem)
                    / static_cast<float>(totalMem) * 100.0f;
                if (mem != m_memoryUtilization) {
                    m_memoryUtilization = mem;
                    emit memoryUtilizationChanged();
                }
            }
        }
    }
#else
    // Memory usage from /proc/meminfo on Linux
    QFile memFile(QStringLiteral("/proc/meminfo"));
    if (memFile.open(QIODevice::ReadOnly)) {
        quint64 memTotal = 0;
        quint64 memAvailable = 0;
        while (!memFile.atEnd()) {
            QString line = memFile.readLine().trimmed();
            if (line.startsWith(QStringLiteral("MemTotal:")))
                memTotal = line.split(QLatin1Char(' '), Qt::SkipEmptyParts)[1].toULongLong();
            else if (line.startsWith(QStringLiteral("MemAvailable:")))
                memAvailable = line.split(QLatin1Char(' '), Qt::SkipEmptyParts)[1].toULongLong();
        }
        if (memTotal > 0) {
            float mem = static_cast<float>(memTotal - memAvailable)
                / static_cast<float>(memTotal) * 100.0f;
            if (mem != m_memoryUtilization) {
                m_memoryUtilization = mem;
                emit memoryUtilizationChanged();
            }
        }
    }
#endif

    // Temperatures from /sys/class/thermal/ (works on both Linux and Android)
    QVariantList temps;
    QDir thermalDir(QStringLiteral("/sys/class/thermal"));
    const auto entries = thermalDir.entryList({QStringLiteral("thermal_zone*")}, QDir::Dirs);
    for (const auto &entry : entries) {
        QFile typeFile(thermalDir.filePath(entry + QStringLiteral("/type")));
        QFile tempFile(thermalDir.filePath(entry + QStringLiteral("/temp")));
        if (typeFile.open(QIODevice::ReadOnly) && tempFile.open(QIODevice::ReadOnly)) {
            QVariantMap t;
            t[QStringLiteral("type")] = QString::fromUtf8(typeFile.readAll().trimmed());
            t[QStringLiteral("temp")] = tempFile.readAll().trimmed().toFloat() / 1000.0f;
            temps.append(t);
        }
    }
    if (temps != m_temperatures) {
        m_temperatures = temps;
        emit temperaturesChanged();
    }
}

// ============================================================================
// vibrate
// ============================================================================

#ifdef Q_OS_ANDROID
void PlatformController::vibrate(quint64 durationMs, bool isNotification)
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid()) {
        qWarning() << "vibrate: unable to get Android context";
        return;
    }

    jint effect = isNotification
        ? static_cast<jint>(0xffffffff) // VibrationEffect.DEFAULT_AMPLITUDE
        : static_cast<jint>(0x00000080);

    QJniObject::callStaticMethod<void>(
        JAVA_VIBRATOR_CLASS, "vibrate",
        "(Landroid/content/Context;JI)V",
        activity.object<jobject>(),
        static_cast<jlong>(durationMs),
        effect);
}
#else
void PlatformController::vibrate(quint64 durationMs, bool isNotification)
{
    Q_UNUSED(durationMs);
    Q_UNUSED(isNotification);
    // No-op on desktop Linux
}
#endif

// ============================================================================
// getSafeAreaInsets
// ============================================================================

#ifdef Q_OS_ANDROID
QVariantMap PlatformController::getSafeAreaInsets()
{
    QVariantMap insets;
    insets[QStringLiteral("top")] = 0;
    insets[QStringLiteral("bottom")] = 0;
    insets[QStringLiteral("left")] = 0;
    insets[QStringLiteral("right")] = 0;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return insets;

    QJniObject window =
        activity.callObjectMethod("getWindow", "()Landroid/view/Window;");
    if (!window.isValid())
        return insets;

    QJniObject decorView =
        window.callObjectMethod("getDecorView", "()Landroid/view/View;");
    if (!decorView.isValid())
        return insets;

    QJniObject rootWindowInsets = decorView.callObjectMethod(
        "getRootWindowInsets", "()Landroid/view/WindowInsets;");
    if (!rootWindowInsets.isValid())
        return insets;

    // Type.systemBars() bitmask = 7 (statusBars | navigationBars | captionBar)
    QJniObject systemBarsInsets = rootWindowInsets.callObjectMethod(
        "getInsets", "(I)Landroid/graphics/Insets;", 7);
    if (systemBarsInsets.isValid()) {
        insets[QStringLiteral("top")] = systemBarsInsets.getField<jint>("top");
        insets[QStringLiteral("bottom")] = systemBarsInsets.getField<jint>("bottom");
        insets[QStringLiteral("left")] = systemBarsInsets.getField<jint>("left");
        insets[QStringLiteral("right")] = systemBarsInsets.getField<jint>("right");
    }

    // Also account for display cutout (notch)
    QJniObject displayCutout = rootWindowInsets.callObjectMethod(
        "getDisplayCutout", "()Landroid/view/DisplayCutout;");
    if (displayCutout.isValid()) {
        insets[QStringLiteral("top")] =
            qMax(insets[QStringLiteral("top")].toInt(),
                 displayCutout.callMethod<jint>("getSafeInsetTop"));
        insets[QStringLiteral("bottom")] =
            qMax(insets[QStringLiteral("bottom")].toInt(),
                 displayCutout.callMethod<jint>("getSafeInsetBottom"));
        insets[QStringLiteral("left")] =
            qMax(insets[QStringLiteral("left")].toInt(),
                 displayCutout.callMethod<jint>("getSafeInsetLeft"));
        insets[QStringLiteral("right")] =
            qMax(insets[QStringLiteral("right")].toInt(),
                 displayCutout.callMethod<jint>("getSafeInsetRight"));
    }

    return insets;
}
#else
QVariantMap PlatformController::getSafeAreaInsets()
{
    QVariantMap result;
    result[QStringLiteral("top")] = 0;
    result[QStringLiteral("bottom")] = 0;
    result[QStringLiteral("left")] = 0;
    result[QStringLiteral("right")] = 0;
    return result;
}
#endif

// ============================================================================
// setEnableRunningInBackground
// ============================================================================

#ifdef Q_OS_ANDROID
void PlatformController::setEnableRunningInBackground(bool enable)
{
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([enable]() {
        QJniObject activity = getAndroidContext();
        if (!activity.isValid()) {
            qWarning() << "setEnableRunningInBackground: unable to get Android context";
            return;
        }

        if (enable) {
            activity.callMethod<void>("acquireWakeLock", "()V");
        } else {
            activity.callMethod<void>("releaseWakeLock", "()V");
        }
    });
}
#else
void PlatformController::setEnableRunningInBackground(bool enable)
{
    Q_UNUSED(enable);
    // No-op on desktop Linux
}
#endif

// ============================================================================
// getCurrentWiFiConnection
// ============================================================================

#ifdef Q_OS_ANDROID
QVariantMap PlatformController::getCurrentWiFiConnection()
{
    QVariantMap result;
    result[QStringLiteral("ssid")] = QString();
    result[QStringLiteral("bssid")] = QString();
    result[QStringLiteral("rssi")] = 0;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return result;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return result;
    }

    QJniObject jsonStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getCurrentConnectionJSON",
        "(Landroid/content/Context;)Ljava/lang/String;",
        activity.object<jobject>());

    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toString().toUtf8());
    if (!doc.isObject())
        return result;

    const QJsonObject o = doc.object();
    result[QStringLiteral("ssid")] = o.value(QStringLiteral("ssid")).toString();
    result[QStringLiteral("bssid")] = o.value(QStringLiteral("bssid")).toString();
    result[QStringLiteral("rssi")] = o.value(QStringLiteral("rssi")).toInt();
    return result;
}
#else
QVariantMap PlatformController::getCurrentWiFiConnection()
{
    QVariantMap result;
    result[QStringLiteral("ssid")] = QString();
    result[QStringLiteral("bssid")] = QString();
    result[QStringLiteral("rssi")] = 0;

    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("-t"), QStringLiteral("-f"),
                QStringLiteral("SSID,BSSID,SIGNAL"),
                QStringLiteral("connection"), QStringLiteral("show"),
                QStringLiteral("--active")});
    if (!proc.waitForFinished(5000))
        return result;

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    if (output.isEmpty())
        return result;

    // Parse first active WiFi connection line (colon-separated from -t flag)
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const auto &line : lines) {
        QStringList fields = line.split(QLatin1Char(':'));
        if (fields.size() >= 3 && !fields[0].isEmpty()) {
            result[QStringLiteral("ssid")] = fields[0];
            result[QStringLiteral("bssid")] = fields[1];
            result[QStringLiteral("rssi")] = fields[2].toInt();
            break;
        }
    }
    return result;
}
#endif

// ============================================================================
// WiFi scanning and connection
// ============================================================================

#ifdef Q_OS_ANDROID
void PlatformController::startWiFiScan()
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "startScan",
        "(Landroid/content/Context;)V",
        activity.object<jobject>());

    emit wifiScanCompleted();
}

QVariantList PlatformController::getWiFiScanResults()
{
    QVariantList results;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return results;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return results;
    }

    QJniObject jsonStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getScanResultsJSON",
        "(Landroid/content/Context;)Ljava/lang/String;",
        activity.object<jobject>());

    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toString().toUtf8());
    if (!doc.isArray())
        return results;

    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        QVariantMap ap;
        ap[QStringLiteral("ssid")] = o.value(QStringLiteral("ssid")).toString();
        ap[QStringLiteral("bssid")] = o.value(QStringLiteral("bssid")).toString();
        ap[QStringLiteral("signal")] = o.value(QStringLiteral("level")).toInt();
        ap[QStringLiteral("freq")] = QString::number(o.value(QStringLiteral("frequency")).toInt());
        results.append(ap);
    }
    return results;
}

void PlatformController::connectToWiFiAP(const QString &ssid, const QString &password)
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    QJniObject jSsid = QJniObject::fromString(ssid);
    QJniObject jBssid = QJniObject::fromString(QString());
    QJniObject jSec = QJniObject::fromString(QStringLiteral("WPA2"));
    QJniObject jPass = QJniObject::fromString(password);

    QJniObject::callStaticMethod<jint>(
        JAVA_WIFI_CLASS, "connectToAP",
        "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;"
        "Ljava/lang/String;Ljava/lang/String;)I",
        activity.object<jobject>(),
        jSsid.object<jstring>(),
        jBssid.object<jstring>(),
        jSec.object<jstring>(),
        jPass.object<jstring>());
}

void PlatformController::disconnectWiFiAP()
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "disconnectAllRequestedAPs",
        "(Landroid/content/Context;)V",
        activity.object<jobject>());
}
#else
void PlatformController::startWiFiScan()
{
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("device"), QStringLiteral("wifi"),
                QStringLiteral("rescan")});
    proc.waitForFinished(10000);
    emit wifiScanCompleted();
}

QVariantList PlatformController::getWiFiScanResults()
{
    QVariantList results;
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("-t"), QStringLiteral("-f"),
                QStringLiteral("SSID,BSSID,SIGNAL,FREQ"),
                QStringLiteral("device"), QStringLiteral("wifi"),
                QStringLiteral("list")});
    if (!proc.waitForFinished(10000))
        return results;

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const auto &line : lines) {
        if (line.trimmed().isEmpty())
            continue;
        // nmcli -t uses colon as delimiter; BSSIDs contain colons escaped with backslash
        // Format: SSID:BSSID:SIGNAL:FREQ
        // We parse from the right since SSID and BSSID can contain special chars
        QStringList fields = line.split(QLatin1Char(':'));
        if (fields.size() >= 4) {
            QVariantMap ap;
            // Last field is FREQ, second-to-last is SIGNAL
            ap[QStringLiteral("freq")] = fields.last();
            ap[QStringLiteral("signal")] = fields[fields.size() - 2].toInt();
            // BSSID is fields[1..size-3] joined (since BSSID has colons)
            // SSID is fields[0]
            ap[QStringLiteral("ssid")] = fields[0];
            QStringList bssidParts;
            for (int i = 1; i < fields.size() - 2; ++i)
                bssidParts.append(fields[i]);
            ap[QStringLiteral("bssid")] = bssidParts.join(QLatin1Char(':'));
            results.append(ap);
        }
    }
    return results;
}

void PlatformController::connectToWiFiAP(const QString &ssid, const QString &password)
{
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("device"), QStringLiteral("wifi"),
                QStringLiteral("connect"), ssid,
                QStringLiteral("password"), password});
    if (!proc.waitForFinished(30000)) {
        qWarning() << "WiFi connect timed out for SSID:" << ssid;
    }
}

void PlatformController::disconnectWiFiAP()
{
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("device"), QStringLiteral("disconnect"),
                QStringLiteral("wlan0")});
    proc.waitForFinished(10000);
}
#endif

// ============================================================================
// refreshWiFiState
// ============================================================================

void PlatformController::refreshWiFiState()
{
    // Update signal strength from the active connection
    QVariantMap conn = getCurrentWiFiConnection();
    int signal = conn.value(QStringLiteral("rssi")).toInt();
    if (signal != m_signalStrength) {
        m_signalStrength = signal;
        emit signalStrengthChanged();
    }
}

// ============================================================================
// getChannelsQualityInfo
// ============================================================================

#ifdef Q_OS_ANDROID
QVariantList PlatformController::getChannelsQualityInfo()
{
    // On Android, derive channel quality from scan results
    QVariantList results;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return results;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS))
        return results;

    QJniObject jsonStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getScanResultsJSON",
        "(Landroid/content/Context;)Ljava/lang/String;",
        activity.object<jobject>());

    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toString().toUtf8());
    if (!doc.isArray())
        return results;

    const QJsonArray arr = doc.array();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        QVariantMap ch;
        ch[QStringLiteral("freq")] = QString::number(o.value(QStringLiteral("frequency")).toInt());
        ch[QStringLiteral("signal")] = o.value(QStringLiteral("level")).toInt();
        results.append(ch);
    }
    return results;
}
#else
QVariantList PlatformController::getChannelsQualityInfo()
{
    QVariantList results;
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("-t"), QStringLiteral("-f"),
                QStringLiteral("FREQ,SIGNAL"),
                QStringLiteral("device"), QStringLiteral("wifi"),
                QStringLiteral("list")});
    if (!proc.waitForFinished(10000))
        return results;

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const auto &line : lines) {
        if (line.trimmed().isEmpty())
            continue;
        QStringList fields = line.split(QLatin1Char(':'));
        if (fields.size() >= 2) {
            QVariantMap ch;
            ch[QStringLiteral("freq")] = fields[0];
            ch[QStringLiteral("signal")] = fields[1].toInt();
            results.append(ch);
        }
    }
    return results;
}
#endif

// ============================================================================
// startMonitoringSignalStrength
// ============================================================================

#ifdef Q_OS_ANDROID
void PlatformController::startMonitoringSignalStrength()
{
    if (m_signalMonitorTimer)
        return;

    // Request location permissions needed for WiFi SSID visibility
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([]() {
        QJniObject activity = getAndroidContext();
        if (!activity.isValid())
            return;

        if (QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
            QJniObject::callStaticMethod<void>(
                JAVA_WIFI_CLASS, "requestWiFiPermissions",
                "(Landroid/content/Context;)V",
                activity.object<jobject>());
        }
    });

    // Initialize the Java-side signal listener on the Android main thread
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([]() {
        QJniObject activity = getAndroidContext();
        if (!activity.isValid())
            return;

        if (!QJniObject::isClassAvailable(JAVA_SIGNAL_CLASS)) {
            qWarning() << "SignalHelper Java class not found";
            return;
        }

        QJniObject::callStaticMethod<void>(
            JAVA_SIGNAL_CLASS, "init",
            "(Landroid/app/Activity;)V",
            activity.object<jobject>());
        QJniObject::callStaticMethod<void>(
            JAVA_SIGNAL_CLASS, "installSignalStrengthListener", "()V");
    });

    // Also set up a timer to poll WiFi signal via refreshWiFiState
    m_signalMonitorTimer = new QTimer(this);
    m_signalMonitorTimer->setInterval(5000);
    connect(m_signalMonitorTimer, &QTimer::timeout, this, &PlatformController::refreshWiFiState);
    m_signalMonitorTimer->start();
}
#else
void PlatformController::startMonitoringSignalStrength()
{
    if (m_signalMonitorTimer)
        return;

    m_signalMonitorTimer = new QTimer(this);
    m_signalMonitorTimer->setInterval(5000);
    connect(m_signalMonitorTimer, &QTimer::timeout, this, &PlatformController::refreshWiFiState);
    m_signalMonitorTimer->start();
}
#endif

// ============================================================================
// Hotspot management
// ============================================================================

#ifdef Q_OS_ANDROID
void PlatformController::setHotspotEnabled(bool enabled)
{
    if (enabled == m_isHotspotEnabled)
        return;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    if (enabled) {
        QJniObject::callStaticMethod<void>(
            JAVA_WIFI_CLASS, "requestNearbyDevicesPermission",
            "(Landroid/content/Context;)V",
            activity.object<jobject>());
    }

    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "setHotspotEnabled",
        "(Landroid/content/Context;Z)V",
        activity.object<jobject>(),
        static_cast<jboolean>(enabled));

    m_isHotspotEnabled = enabled;
    emit isHotspotEnabledChanged();
}

void PlatformController::setLocalHotspotEnabled(bool enabled)
{
    m_isLocalHotspotEnabled = enabled;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "setLocalHotspotEnabled",
        "(Landroid/content/Context;Z)V",
        activity.object<jobject>(),
        static_cast<jboolean>(enabled));
}

bool PlatformController::isLocalHotspotEnabled() const
{
    return m_isLocalHotspotEnabled;
}

QString PlatformController::getHotspotIPAddress()
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return {};

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS))
        return {};

    QJniObject ipStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getHotspotIPAddress",
        "(Landroid/content/Context;)Ljava/lang/String;",
        activity.object<jobject>());

    return ipStr.toString();
}

QVariantMap PlatformController::getLocalOnlyHotspotInfo()
{
    QVariantMap info;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return info;
    }

    QJniObject jsonStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getLocalOnlyHotspotInfoJSON",
        "()Ljava/lang/String;");

    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toString().toUtf8());
    if (doc.isObject()) {
        const QJsonObject o = doc.object();
        info[QStringLiteral("ssid")] = o.value(QStringLiteral("ssid")).toString();
        info[QStringLiteral("password")] = o.value(QStringLiteral("psk")).toString();
    }
    info[QStringLiteral("ipAddress")] = getHotspotIPAddress();
    info[QStringLiteral("enabled")] = m_isLocalHotspotEnabled;
    return info;
}

QVariantMap PlatformController::getHotspotConfiguration()
{
    QVariantMap config;

    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return config;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS))
        return config;

    QJniObject jsonStr = QJniObject::callStaticObjectMethod(
        JAVA_WIFI_CLASS, "getHotspotConfigurationJSON",
        "(Landroid/content/Context;)Ljava/lang/String;",
        activity.object<jobject>());

    const QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toString().toUtf8());
    if (doc.isObject()) {
        const QJsonObject o = doc.object();
        config[QStringLiteral("ssid")] = o.value(QStringLiteral("ssid")).toString();
        config[QStringLiteral("password")] = o.value(QStringLiteral("psk")).toString();
    }
    return config;
}

void PlatformController::saveHotspotConfiguration(const QString &ssid, const QString &password)
{
    QJniObject activity = getAndroidContext();
    if (!activity.isValid())
        return;

    if (!QJniObject::isClassAvailable(JAVA_WIFI_CLASS)) {
        qWarning() << "WiFiHelper Java class not found";
        return;
    }

    QJniObject jSsid = QJniObject::fromString(ssid);
    QJniObject jPsk = QJniObject::fromString(password);

    QJniObject::callStaticMethod<void>(
        JAVA_WIFI_CLASS, "saveHotspotConfiguration",
        "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;)V",
        activity.object<jobject>(),
        jSsid.object<jstring>(),
        jPsk.object<jstring>());
}
#else
void PlatformController::setHotspotEnabled(bool enabled)
{
    if (enabled == m_isHotspotEnabled)
        return;

    QProcess proc;
    if (enabled) {
        proc.start(QStringLiteral("nmcli"),
                   {QStringLiteral("connection"), QStringLiteral("up"),
                    QStringLiteral("Hotspot")});
    } else {
        proc.start(QStringLiteral("nmcli"),
                   {QStringLiteral("connection"), QStringLiteral("down"),
                    QStringLiteral("Hotspot")});
    }
    if (proc.waitForFinished(15000)) {
        m_isHotspotEnabled = enabled;
        emit isHotspotEnabledChanged();
    }
}

void PlatformController::setLocalHotspotEnabled(bool enabled)
{
    m_isLocalHotspotEnabled = enabled;
    setHotspotEnabled(enabled);
}

bool PlatformController::isLocalHotspotEnabled() const
{
    return m_isLocalHotspotEnabled;
}

QString PlatformController::getHotspotIPAddress()
{
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("-t"), QStringLiteral("-f"),
                QStringLiteral("IP4.ADDRESS"),
                QStringLiteral("connection"), QStringLiteral("show"),
                QStringLiteral("Hotspot")});
    if (!proc.waitForFinished(5000))
        return {};

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    // Format: IP4.ADDRESS[1]:192.168.x.x/24
    if (output.contains(QLatin1Char(':'))) {
        QString addr = output.section(QLatin1Char(':'), 1).trimmed();
        // Strip CIDR suffix
        if (addr.contains(QLatin1Char('/')))
            addr = addr.section(QLatin1Char('/'), 0, 0);
        return addr;
    }
    return {};
}

QVariantMap PlatformController::getLocalOnlyHotspotInfo()
{
    QVariantMap info;
    QVariantMap config = getHotspotConfiguration();
    info[QStringLiteral("ssid")] = config.value(QStringLiteral("ssid"));
    info[QStringLiteral("password")] = config.value(QStringLiteral("password"));
    info[QStringLiteral("ipAddress")] = getHotspotIPAddress();
    info[QStringLiteral("enabled")] = m_isLocalHotspotEnabled;
    return info;
}

QVariantMap PlatformController::getHotspotConfiguration()
{
    QVariantMap config;
    QProcess proc;
    proc.start(QStringLiteral("nmcli"),
               {QStringLiteral("-t"), QStringLiteral("-f"),
                QStringLiteral("802-11-wireless.ssid,802-11-wireless-security.psk"),
                QStringLiteral("connection"), QStringLiteral("show"),
                QStringLiteral("Hotspot")});
    if (!proc.waitForFinished(5000))
        return config;

    const QString output = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    const QStringList lines = output.split(QLatin1Char('\n'));
    for (const auto &line : lines) {
        if (line.startsWith(QStringLiteral("802-11-wireless.ssid:")))
            config[QStringLiteral("ssid")] = line.section(QLatin1Char(':'), 1).trimmed();
        else if (line.startsWith(QStringLiteral("802-11-wireless-security.psk:")))
            config[QStringLiteral("password")] = line.section(QLatin1Char(':'), 1).trimmed();
    }
    return config;
}

void PlatformController::saveHotspotConfiguration(const QString &ssid, const QString &password)
{
    // Check if Hotspot connection already exists
    QProcess checkProc;
    checkProc.start(QStringLiteral("nmcli"),
                    {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("NAME"),
                     QStringLiteral("connection"), QStringLiteral("show")});
    checkProc.waitForFinished(5000);
    const QString existing = QString::fromUtf8(checkProc.readAllStandardOutput());

    if (existing.contains(QStringLiteral("Hotspot"))) {
        // Modify existing connection
        QProcess modSsid;
        modSsid.start(QStringLiteral("nmcli"),
                       {QStringLiteral("connection"), QStringLiteral("modify"),
                        QStringLiteral("Hotspot"),
                        QStringLiteral("802-11-wireless.ssid"), ssid});
        modSsid.waitForFinished(5000);

        QProcess modPsk;
        modPsk.start(QStringLiteral("nmcli"),
                      {QStringLiteral("connection"), QStringLiteral("modify"),
                       QStringLiteral("Hotspot"),
                       QStringLiteral("802-11-wireless-security.psk"), password});
        modPsk.waitForFinished(5000);
    } else {
        // Create new hotspot connection
        QProcess createProc;
        createProc.start(QStringLiteral("nmcli"),
                          {QStringLiteral("connection"), QStringLiteral("add"),
                           QStringLiteral("type"), QStringLiteral("wifi"),
                           QStringLiteral("con-name"), QStringLiteral("Hotspot"),
                           QStringLiteral("autoconnect"), QStringLiteral("no"),
                           QStringLiteral("wifi.mode"), QStringLiteral("ap"),
                           QStringLiteral("wifi.ssid"), ssid,
                           QStringLiteral("wifi-sec.key-mgmt"), QStringLiteral("wpa-psk"),
                           QStringLiteral("wifi-sec.psk"), password,
                           QStringLiteral("ipv4.method"), QStringLiteral("shared")});
        createProc.waitForFinished(10000);
    }
}
#endif

// ============================================================================
// JNI callback for signal strength changes (Android only)
// ============================================================================

#ifdef Q_OS_ANDROID
extern "C" {
JNIEXPORT void JNICALL
Java_org_xaionaro_wingout2_SignalHelper_onSignalStrengthChanged(
    JNIEnv * /*env*/, jclass /*clazz*/, jint strength)
{
    if (s_instance) {
        // strength is 0-4 from TelephonyManager; trigger a WiFi state
        // refresh on the Qt thread to keep signal info up to date.
        QMetaObject::invokeMethod(s_instance,
            &PlatformController::refreshWiFiState,
            Qt::QueuedConnection);
    }
}
} // extern "C"
#endif
