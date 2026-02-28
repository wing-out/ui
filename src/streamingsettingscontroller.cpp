#include "streamingsettingscontroller.h"
#include <QSettings>
#include <QDebug>

StreamingSettingsController::StreamingSettingsController(QObject *parent)
    : QObject(parent)
{
    loadSettings();
}

StreamingSettingsController::~StreamingSettingsController() = default;

bool StreamingSettingsController::isActive() const { return m_active; }
int StreamingSettingsController::width() const { return m_width; }
int StreamingSettingsController::height() const { return m_height; }
int StreamingSettingsController::fps() const { return m_fps; }
int StreamingSettingsController::bitrateKbps() const { return m_bitrateKbps; }
QString StreamingSettingsController::preferredCamera() const { return m_preferredCamera; }

void StreamingSettingsController::setWidth(int w)
{
    if (m_width != w) {
        m_width = w;
        emit widthChanged();
    }
}

void StreamingSettingsController::setHeight(int h)
{
    if (m_height != h) {
        m_height = h;
        emit heightChanged();
    }
}

void StreamingSettingsController::setFps(int f)
{
    if (m_fps != f) {
        m_fps = f;
        emit fpsChanged();
    }
}

void StreamingSettingsController::setBitrateKbps(int br)
{
    if (m_bitrateKbps != br) {
        m_bitrateKbps = br;
        emit bitrateKbpsChanged();
    }
}

void StreamingSettingsController::setPreferredCamera(const QString &cam)
{
    if (m_preferredCamera != cam) {
        m_preferredCamera = cam;
        emit preferredCameraChanged();
    }
}

void StreamingSettingsController::activate()
{
    if (!m_active) {
        m_active = true;
        emit activeChanged();
    }
}

void StreamingSettingsController::deactivate()
{
    if (m_active) {
        m_active = false;
        emit activeChanged();
    }
}

void StreamingSettingsController::saveSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("StreamingSettings"));
    settings.setValue(QStringLiteral("width"), m_width);
    settings.setValue(QStringLiteral("height"), m_height);
    settings.setValue(QStringLiteral("fps"), m_fps);
    settings.setValue(QStringLiteral("bitrateKbps"), m_bitrateKbps);
    settings.setValue(QStringLiteral("preferredCamera"), m_preferredCamera);
    settings.endGroup();
}

void StreamingSettingsController::loadSettings()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("StreamingSettings"));
    m_width = settings.value(QStringLiteral("width"), 1920).toInt();
    m_height = settings.value(QStringLiteral("height"), 1080).toInt();
    m_fps = settings.value(QStringLiteral("fps"), 30).toInt();
    m_bitrateKbps = settings.value(QStringLiteral("bitrateKbps"), 6000).toInt();
    m_preferredCamera = settings.value(QStringLiteral("preferredCamera")).toString();
    settings.endGroup();
}
