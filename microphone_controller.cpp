#include "microphone_controller.h"

#include <QtCore/QLoggingCategory>
#include <QtCore/QHash>
#include <QTimer>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#endif

Q_LOGGING_CATEGORY(lcMic, "wingout.microphone")

// Maps android.media.AudioDeviceInfo.TYPE_* constants to human-readable
// strings. Keep in sync with the Android SDK; values used here are the
// numeric constants from AudioDeviceInfo (API 23+).
static QString micTypeName(int type) {
    switch (type) {
    case 0:  return QStringLiteral("Unknown");
    case 1:  return QStringLiteral("Earpiece");
    case 2:  return QStringLiteral("Speaker");
    case 3:  return QStringLiteral("Wired headset");
    case 4:  return QStringLiteral("Wired headphones");
    case 5:  return QStringLiteral("Analog line");
    case 6:  return QStringLiteral("Digital line");
    case 7:  return QStringLiteral("Bluetooth (SCO)");
    case 8:  return QStringLiteral("Bluetooth (A2DP)");
    case 9:  return QStringLiteral("HDMI");
    case 10: return QStringLiteral("HDMI ARC");
    case 11: return QStringLiteral("USB device");
    case 12: return QStringLiteral("USB accessory");
    case 13: return QStringLiteral("Dock");
    case 14: return QStringLiteral("FM radio");
    case 15: return QStringLiteral("Built-in mic");
    case 16: return QStringLiteral("FM tuner");
    case 17: return QStringLiteral("TV tuner");
    case 18: return QStringLiteral("Telephony");
    case 19: return QStringLiteral("AUX line");
    case 20: return QStringLiteral("IP");
    case 21: return QStringLiteral("Bus");
    case 22: return QStringLiteral("USB headset");
    case 23: return QStringLiteral("Hearing aid");
    case 24: return QStringLiteral("Speaker (safe)");
    case 25: return QStringLiteral("Remote submix");
    case 26: return QStringLiteral("BLE headset");
    case 27: return QStringLiteral("BLE speaker");
    case 28: return QStringLiteral("Echo reference");
    case 29: return QStringLiteral("HDMI eARC");
    case 30: return QStringLiteral("BLE broadcast");
    case 31: return QStringLiteral("Analog dock");
    default: return QStringLiteral("Type %1").arg(type);
    }
}

MicrophoneController::MicrophoneController(QObject *parent) : QObject(parent) {
    refresh();
    m_pollTimer.setInterval(2000);
    connect(&m_pollTimer, &QTimer::timeout, this, &MicrophoneController::pollDevices);
    m_pollTimer.start();
}

QVariantList MicrophoneController::devices() const { return m_devices; }

QVariantList MicrophoneController::buildDevices() const {
    QVariantList result;

#ifdef Q_OS_ANDROID
    // Get Android Activity context
    QJniObject activity = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative", "activity",
        "()Landroid/app/Activity;");
    if (!activity.isValid()) {
        qCWarning(lcMic) << "no Android activity";
        return result;
    }

    // context.getSystemService("audio") -> AudioManager
    QJniObject service = QJniObject::fromString(QStringLiteral("audio"));
    QJniObject am = activity.callObjectMethod(
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        service.object<jstring>());
    if (!am.isValid()) {
        qCWarning(lcMic) << "no AudioManager";
        return result;
    }

    // GET_DEVICES_INPUTS = 1
    QJniObject array = am.callObjectMethod(
        "getDevices",
        "(I)[Landroid/media/AudioDeviceInfo;",
        1);
    if (!array.isValid()) {
        return result;
    }

    QJniEnvironment env;
    jobjectArray jarr = array.object<jobjectArray>();
    jsize n = env->GetArrayLength(jarr);
    for (jsize i = 0; i < n; ++i) {
        QJniObject info = QJniObject::fromLocalRef(env->GetObjectArrayElement(jarr, i));
        if (!info.isValid()) continue;

        jint id = info.callMethod<jint>("getId");
        jint type = info.callMethod<jint>("getType");
        QJniObject nameSeq = info.callObjectMethod(
            "getProductName", "()Ljava/lang/CharSequence;");
        QString name;
        if (nameSeq.isValid()) {
            QJniObject nameStr = nameSeq.callObjectMethod(
                "toString", "()Ljava/lang/String;");
            name = nameStr.toString();
        }
        // getAddress() distinguishes physical mics that share Java type
        // TYPE_BUILTIN_MIC=15 (e.g. HAL bottom-mic vs back-mic on Pixel
        // both surface as TYPE_BUILTIN_MIC, but with addresses "bottom"
        // and "back" respectively).
        QJniObject addrObj = info.callObjectMethod(
            "getAddress", "()Ljava/lang/String;");
        const QString address = addrObj.isValid() ? addrObj.toString() : QString();
        const QString tname = micTypeName(int(type));
        const QString typedSuffix = address.isEmpty()
            ? tname
            : QStringLiteral("%1, %2").arg(tname, address);
        const QString label = name.isEmpty()
            ? typedSuffix
            : QStringLiteral("%1 (%2)").arg(name, typedSuffix);
        QVariantMap m;
        m[QStringLiteral("id")] = int(id);
        m[QStringLiteral("name")] = name;
        m[QStringLiteral("type")] = int(type);
        m[QStringLiteral("typeName")] = tname;
        m[QStringLiteral("address")] = address;
        m[QStringLiteral("displayLabel")] = label;
        result.append(m);
    }
#else
    // Desktop stub: ensure QML doesn't break outside Android.
    {
        const int type = 15; // TYPE_BUILTIN_MIC
        const QString name = QStringLiteral("Default");
        const QString tname = micTypeName(type);
        QVariantMap m;
        m[QStringLiteral("id")] = 0;
        m[QStringLiteral("name")] = name;
        m[QStringLiteral("type")] = type;
        m[QStringLiteral("typeName")] = tname;
        m[QStringLiteral("displayLabel")] = QStringLiteral("%1 (%2)").arg(name, tname);
        result.append(m);
    }
#endif

    // Do NOT deduplicate: distinct AudioDeviceInfo IDs are distinct
    // physical mics, even if Java collapses HAL types (e.g. BUILTIN_MIC
    // and BACK_MIC both surface as TYPE_BUILTIN_MIC). The address suffix
    // above disambiguates Pixel-style bottom/back mics. As a fallback
    // for any residual same-label collisions (e.g. empty addresses),
    // append " #<id>" so the user can still tell entries apart.
    QHash<QString, int> labelCount;
    for (const QVariant &v : std::as_const(result)) {
        labelCount[v.toMap().value(QStringLiteral("displayLabel")).toString()] += 1;
    }
    for (QVariant &v : result) {
        QVariantMap m = v.toMap();
        const QString label = m.value(QStringLiteral("displayLabel")).toString();
        if (labelCount.value(label, 0) > 1) {
            m[QStringLiteral("displayLabel")] =
                QStringLiteral("%1 #%2").arg(label).arg(m.value(QStringLiteral("id")).toInt());
            v = m;
        }
    }

    return result;
}

void MicrophoneController::refresh() {
    m_devices = buildDevices();
    QStringList ids;
    for (const QVariant &v : std::as_const(m_devices)) {
        ids.append(QString::number(v.toMap().value(QStringLiteral("id")).toInt()));
    }
    ids.sort();
    m_lastDeviceIds = ids;
    emit devicesChanged();
}

void MicrophoneController::pollDevices() {
    QVariantList rebuilt = buildDevices();
    QStringList ids;
    for (const QVariant &v : std::as_const(rebuilt)) {
        ids.append(QString::number(v.toMap().value(QStringLiteral("id")).toInt()));
    }
    ids.sort();
    if (ids == m_lastDeviceIds) {
        return;
    }
    m_devices = rebuilt;
    m_lastDeviceIds = ids;
    emit devicesChanged();
}
