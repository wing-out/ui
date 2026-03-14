import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import Qt.labs.settings

import "components" as Components
import "pages" as Pages
import "dialogs" as Dialogs

ApplicationWindow {
    id: window
    objectName: "mainWindow"

    width: 1080
    height: 1920
    visible: true
    title: "WingOut"
    color: Theme.background

    Material.theme: Material.Dark
    Material.accent: Theme.accentPrimary

    // Persistent settings
    Settings {
        id: appSettings
        property string backendHost: ""
        property string backendMode: "remote"
        property string remoteFFStreamAddr: ""
        property string remoteStreamDAddr: ""
        property string remoteAVDAddr: ""
        property string previewRTMPUrl: ""
        property string previewRTMPPort: "1945"
        property string manualInputFPS: ""
        property string colorTheme: "dark"
        property string chatTimestampFormat: "mm"
        property bool ttsEnabled: false
        property bool ttsUsernames: false
        property bool vibrateEnabled: false
        property bool soundEnabled: true
        property int chatFontSize: 16
        property bool stopDaemonOnClose: true
    }

    // Start embedded daemon and/or connect to backend
    function connectBackend() {
        if (appSettings.backendMode === "embedded" || appSettings.backendMode === "hybrid") {
            var addr = backendController.startEmbeddedDaemon(
                appSettings.remoteStreamDAddr, appSettings.remoteFFStreamAddr)
            if (addr !== "") {
                appSettings.backendHost = addr
                backendController.serverUri = addr
                appLogModel.addLog("Embedded daemon started at " + addr, false)
            } else {
                appLogModel.addLog("Failed to start embedded daemon", true)
            }
        }
        if (appSettings.backendHost !== "") {
            backendController.serverUri = appSettings.backendHost
        }
        if (appSettings.remoteFFStreamAddr !== "" || appSettings.remoteStreamDAddr !== "" || appSettings.remoteAVDAddr !== "") {
            backendController.setBackendAddresses(
                appSettings.remoteFFStreamAddr, appSettings.remoteStreamDAddr,
                appSettings.remoteAVDAddr,
                function() { console.log("Backend addresses configured") },
                function(err) { appLogModel.addLog("setBackendAddresses error: " + err, true) }
            )
        }
    }

    Component.onCompleted: {
        Theme.applyTheme(appSettings.colorTheme)
        backendController.setStopDaemonOnClose(appSettings.stopDaemonOnClose)
        platformInstance.startMonitoringSignalStrength()
        connectBackend()
    }

    Connections {
        target: appSettings
        function onStopDaemonOnCloseChanged() {
            backendController.setStopDaemonOnClose(appSettings.stopDaemonOnClose)
        }
    }

    // Periodic resource updates
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: platformInstance.updateResources()
    }

    // Sub-service connectivity (probed when backend is connected)
    property bool streamdAlive: false
    property bool ffstreamAlive: false

    Timer {
        interval: 2000
        running: backendController.connected && !window.setupRequired
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            backendController.ping("health",
                function() { window.streamdAlive = true },
                function() { window.streamdAlive = false }
            )
            backendController.getBitRates(
                function() { window.ffstreamAlive = true },
                function() { window.ffstreamAlive = false }
            )
        }
    }
    onStreamdAliveChanged: if (!backendController.connected) streamdAlive = false
    onFfstreamAliveChanged: if (!backendController.connected) ffstreamAlive = false

    // Application log model with O(1) duplicate collapsing via index map
    ListModel {
        id: appLogModel
        property int errorCount: 0
        // JS object mapping "message\nisError" → model index for O(1) lookup
        property var _indexMap: ({})

        function _formatTime(d) {
            return String(d.getHours()).padStart(2, '0') + ":"
                 + String(d.getMinutes()).padStart(2, '0') + ":"
                 + String(d.getSeconds()).padStart(2, '0')
        }

        function _key(message, isError) {
            return message + "\n" + (isError ? "1" : "0")
        }

        function addLog(message, isError) {
            var now = new Date()
            var time = _formatTime(now)
            var k = _key(message, isError)
            var idx = _indexMap[k]
            if (idx !== undefined && idx < count) {
                // Verify the entry at idx still matches (guard against stale map)
                var existing = get(idx)
                if (existing.message === message && existing.isError === isError) {
                    set(idx, {
                        "message": message, "isError": isError,
                        "time": existing.time, "lastTime": time,
                        "repeatCount": (existing.repeatCount || 1) + 1
                    })
                    return
                }
            }
            append({ "message": message, "isError": isError, "time": time, "lastTime": "", "repeatCount": 1 })
            _indexMap[k] = count - 1
            if (isError) errorCount++
            if (count > 500) {
                // Evict oldest entries and rebuild the map
                var toRemove = count - 500
                for (var i = 0; i < toRemove; i++) remove(0)
                _rebuildMap()
            }
        }

        function _rebuildMap() {
            var m = {}
            for (var i = 0; i < count; i++) {
                var row = get(i)
                m[_key(row.message, row.isError)] = i
            }
            _indexMap = m
        }

        function clearAll() {
            errorCount = 0
            _indexMap = {}
            clear()
        }
    }

    // Logs page index (must match StackLayout order)
    readonly property int logsPageIndex: 9

    // Check if setup is needed (embedded mode auto-starts daemon, no manual setup required)
    property bool setupRequired: appSettings.backendHost === "" && appSettings.backendMode !== "embedded"

    // Initial setup dialog
    Loader {
        id: setupLoader
        active: window.setupRequired
        anchors.fill: parent
        z: 100
        sourceComponent: Dialogs.InitialSetup {
            onSetupComplete: function(host, mode, ffstreamAddr, streamdAddr) {
                appSettings.backendMode = mode
                appSettings.remoteFFStreamAddr = ffstreamAddr
                appSettings.remoteStreamDAddr = streamdAddr
                if (mode === "embedded" || mode === "hybrid") {
                    var addr = backendController.startEmbeddedDaemon(streamdAddr, ffstreamAddr)
                    if (addr !== "") {
                        appSettings.backendHost = addr
                        backendController.serverUri = addr
                        appLogModel.addLog("Embedded daemon started at " + addr, false)
                    } else {
                        appLogModel.addLog("Failed to start embedded daemon", true)
                        appSettings.backendHost = host
                        backendController.serverUri = host
                    }
                } else {
                    appSettings.backendHost = host
                    backendController.serverUri = host
                }
                if (ffstreamAddr !== "" || streamdAddr !== "") {
                    backendController.setBackendAddresses(
                        ffstreamAddr, streamdAddr, "",
                        function() { console.log("Backend addresses configured") },
                        function(err) { appLogModel.addLog("setBackendAddresses error: " + err, true) }
                    )
                }
                window.setupRequired = false
            }
        }
    }

    // Main content (loaded after setup)
    Item {
        anchors.fill: parent
        visible: !window.setupRequired
        enabled: !window.setupRequired

        // Navigation menu overlay
        Components.NavMenu {
            id: navMenu
            objectName: "navMenu"
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            x: navMenu.isOpen ? 0 : -navMenu.width
            z: 50
            currentIndex: pageStack.currentIndex

            Behavior on x { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

            onPageSelected: function(index) {
                pageStack.currentIndex = index
                navMenu.isOpen = false
            }
        }

        // Dim overlay when menu is open
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.5)
            visible: navMenu.isOpen
            z: 40

            MouseArea {
                anchors.fill: parent
                onClicked: navMenu.isOpen = false
            }

            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        // Top bar
        Rectangle {
            id: topBar
            objectName: "topBar"
            Accessible.name: "topBar"
            Accessible.role: Accessible.ToolBar
            width: parent.width
            height: 56
            color: Theme.backgroundSecondary
            z: 30
            enabled: !lockOverlay.locked

            Row {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingSmall
                anchors.rightMargin: Theme.spacingSmall
                spacing: Theme.spacingSmall

                // Menu button
                Components.GlassButton {
                    objectName: "menuButton"
                    text: "\ue5d2"
                    font.family: Theme.iconFont
                    width: 48
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: navMenu.isOpen = !navMenu.isOpen
                }

                // Page title
                Text {
                    id: pageTitleText
                    Accessible.name: "pageTitle: " + pageTitleText.text
                    text: {
                        var titles = ["Dashboard", "Status", "Cameras", "DJI Control", "Chat",
                                      "Players", "Restreams", "Monitor", "Profiles", "Logs", "Settings", "AVD Filters"]
                        return titles[pageStack.currentIndex] || "WingOut"
                    }
                    font.pixelSize: Theme.fontLarge
                    font.weight: Font.Medium
                    color: Theme.textPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item { Layout.fillWidth: true; width: 10 }

                // Connection status: single badge when disconnected, two compact badges when connected
                Components.StatusBadge {
                    visible: !backendController.connected
                    label: "Disconnected"
                    statusColor: Theme.error
                    active: false
                    anchors.verticalCenter: parent.verticalCenter
                }
                Components.StatusBadge {
                    objectName: "streamdStatus"
                    visible: backendController.connected
                    label: "SD"
                    statusColor: window.streamdAlive ? Theme.success : Theme.error
                    active: window.streamdAlive
                    anchors.verticalCenter: parent.verticalCenter
                }
                Components.StatusBadge {
                    objectName: "ffstreamStatus"
                    visible: backendController.connected
                    label: "FF"
                    statusColor: window.ffstreamAlive ? Theme.success : Theme.error
                    active: window.ffstreamAlive
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Error counter — navigates to Logs page with error filter
                Rectangle {
                    objectName: "errorCounter"
                    visible: appLogModel.errorCount > 0
                    width: errorCounterRow.implicitWidth + Theme.spacingSmall * 2
                    height: 28
                    radius: height / 2
                    color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.3)
                    anchors.verticalCenter: parent.verticalCenter

                    Row {
                        id: errorCounterRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingTiny

                        Text {
                            text: "\ue002"
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.fontSmall
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: appLogModel.errorCount.toString()
                            font.pixelSize: Theme.fontSmall
                            font.weight: Font.Bold
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pageStack.currentIndex = window.logsPageIndex
                            logsPageItem.filterErrors = true
                        }
                    }
                }

                // Spacer reserving room for the lock button (rendered outside the Row for z-ordering)
                Item {
                    id: lockButtonPlaceholder
                    width: 48
                    height: 40
                    visible: pageStack.currentIndex === 0
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Page stack
        StackLayout {
            id: pageStack
            objectName: "pageStack"
            anchors.top: topBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            enabled: !lockOverlay.locked
            currentIndex: 0

            Pages.DashboardPage {
                objectName: "dashboardPage"
                controller: backendController
                settings: appSettings
            }
            Pages.StatusPage {
                objectName: "statusPage"
                controller: backendController
            }
            Pages.CamerasPage {
                objectName: "camerasPage"
                controller: backendController
            }
            Pages.DJIControlPage {
                objectName: "djiControlPage"
                controller: backendController
            }
            Pages.ChatPage {
                objectName: "chatPage"
                controller: backendController
                settings: appSettings
            }
            Pages.PlayersPage {
                objectName: "playersPage"
                controller: backendController
            }
            Pages.RestreamsPage {
                objectName: "restreamsPage"
                controller: backendController
            }
            Pages.MonitorPage {
                objectName: "monitorPage"
                controller: backendController
            }
            Pages.ProfilesPage {
                objectName: "profilesPage"
                controller: backendController
            }
            Pages.LogsPage {
                id: logsPageItem
                objectName: "logsPage"
                logModel: appLogModel
            }
            Pages.SettingsPage {
                objectName: "settingsPage"
                controller: backendController
                settings: appSettings
            }
            Pages.AVDPage {
                objectName: "avdPage"
                controller: backendController
            }
        }

        // Lock overlay — transparent, blocks all touch when locked
        Components.SwipeLockOverlay {
            id: lockOverlay
            anchors.fill: parent
            z: 60
        }

        // Lock button rendered above the overlay so it stays interactive when locked.
        // Positioned to overlap the placeholder in the top bar Row.
        Components.GlassButton {
            id: lockButton
            objectName: "lockButton"
            text: lockOverlay.locked ? "\ue898" : "\ue899"
            font.family: Theme.iconFont
            filled: lockOverlay.locked
            width: 48
            height: 40
            z: 70
            visible: pageStack.currentIndex === 0
            // Position tracks the placeholder inside the top bar Row
            x: topBar.x + Theme.spacingSmall + lockButtonPlaceholder.x
            y: topBar.y + (topBar.height - height) / 2

            property real _lastClickTime: 0

            onClicked: {
                if (!lockOverlay.locked) {
                    lockOverlay.locked = true
                } else {
                    var now = Date.now()
                    if (now - _lastClickTime < 400) {
                        lockOverlay.locked = false
                        _lastClickTime = 0
                    } else {
                        _lastClickTime = now
                    }
                }
            }
        }

        Connections {
            target: backendController
            function onErrorOccurred(error) { appLogModel.addLog(error, true) }
        }
    }

    // Keyboard shortcuts
    Shortcut {
        sequence: "Space"
        enabled: pageStack.currentIndex === 0
        onActivated: lockOverlay.locked = !lockOverlay.locked
    }
}
