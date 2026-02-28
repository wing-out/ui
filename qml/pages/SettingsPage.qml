import QtQuick
import QtQuick.Controls.Material
import QtQuick.Layouts
import "../components" as Components
import WingOut

Item {
    id: root
    required property var controller
    required property var settings

    Accessible.name: "settingsPage"
    Accessible.role: Accessible.Pane

    property string configYaml: ""
    property int loggingLevel: 5

    function loadConfig() {
        controller.getConfig(
            function(config) { root.configYaml = config },
            function(err) { console.warn("getConfig error:", err) }
        )
    }

    Component.onCompleted: {
        loadConfig()
        controller.getLoggingLevel(
            function(level) { root.loggingLevel = level },
            function(err) { console.warn("getLoggingLevel error:", err) }
        )
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingMedium
        contentHeight: col.implicitHeight
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: Theme.spacingMedium

            // Theme selection
            Text {
                text: "Theme"
                Accessible.name: "Theme"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Flow {
                id: themeButtonsFlow
                objectName: "themeButtonsFlow"
                width: parent.width
                spacing: Theme.spacingSmall

                Repeater {
                    model: Theme.themeNames
                    Components.GlassButton {
                        objectName: "theme_" + modelData
                        text: Theme.themeLabels[index]
                        filled: Theme.currentTheme === modelData
                        onClicked: {
                            root.settings.colorTheme = modelData
                            Theme.applyTheme(modelData)
                        }
                    }
                }
            }

            // Connection settings
            Text {
                text: "Connection"
                Accessible.name: "Connection"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: connCol.implicitHeight + Theme.spacingLarge * 2

                Column {
                    id: connCol
                    anchors.fill: parent
                    spacing: Theme.spacingSmall

                    Text {
                        text: "Backend Host"
                        Accessible.name: "Backend Host"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }

                    Components.SearchField {
                        id: backendHostField
                        width: parent.width
                        text: root.settings.backendHost
                        placeholder: "e.g. 127.0.0.1:3595"
                        onTextChanged: root.settings.backendHost = text
                    }

                    Text {
                        text: "FFStream Address"
                        Accessible.name: "FFStream Address"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                        topPadding: Theme.spacingSmall
                    }

                    Components.SearchField {
                        id: ffstreamAddrField
                        objectName: "ffstreamAddrField"
                        width: parent.width
                        text: root.settings.remoteFFStreamAddr
                        placeholder: "e.g. 127.0.0.1:3593"
                        onTextChanged: root.settings.remoteFFStreamAddr = text
                    }

                    Text {
                        text: "StreamD Address"
                        Accessible.name: "StreamD Address"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                        topPadding: Theme.spacingSmall
                    }

                    Components.SearchField {
                        id: streamdAddrField
                        objectName: "streamdAddrField"
                        width: parent.width
                        text: root.settings.remoteStreamDAddr
                        placeholder: "e.g. 127.0.0.1:3594"
                        onTextChanged: root.settings.remoteStreamDAddr = text
                    }

                    Components.GlassButton {
                        objectName: "applyBackendAddresses"
                        text: "Apply Backend Addresses"
                        filled: true
                        onClicked: {
                            controller.setBackendAddresses(
                                ffstreamAddrField.text, streamdAddrField.text,
                                function() { console.log("Backend addresses updated") },
                                function(err) { console.warn("setBackendAddresses error:", err) }
                            )
                        }
                    }

                    Text {
                        text: "Backend Mode"
                        Accessible.name: "Backend Mode"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                        topPadding: Theme.spacingSmall
                    }

                    Row {
                        spacing: Theme.spacingSmall

                        Components.GlassButton {
                            objectName: "settingsModeEmbedded"
                            text: "Embedded"
                            filled: root.settings.backendMode === "embedded"
                            onClicked: root.settings.backendMode = "embedded"
                        }
                        Components.GlassButton {
                            objectName: "settingsModeRemote"
                            text: "Remote"
                            filled: root.settings.backendMode === "remote"
                            onClicked: root.settings.backendMode = "remote"
                        }
                        Components.GlassButton {
                            objectName: "settingsModeHybrid"
                            text: "Hybrid"
                            filled: root.settings.backendMode === "hybrid"
                            onClicked: root.settings.backendMode = "hybrid"
                        }
                    }
                }
            }

            // Config editor
            Text {
                text: "Configuration"
                Accessible.name: "Configuration"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: 300

                ScrollView {
                    anchors.fill: parent
                    TextArea {
                        id: configEditor
                        objectName: "configEditor"
                        text: root.configYaml
                        Accessible.name: "configEditor"
                        Accessible.description: root.configYaml
                        font.family: "monospace"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textPrimary
                        wrapMode: TextEdit.Wrap
                        background: null
                    }
                }
            }

            Row {
                spacing: Theme.spacingSmall

                Components.GlassButton {
                    objectName: "configApplyButton"
                    text: "Apply"
                    filled: true
                    onClicked: {
                        controller.setConfig(configEditor.text,
                            function() { console.log("Config applied") },
                            function(err) { console.error("setConfig error:", err) }
                        )
                    }
                }

                Components.GlassButton {
                    objectName: "configSaveButton"
                    text: "Save"
                    onClicked: {
                        controller.saveConfig(
                            function() { console.log("Config saved") },
                            function(err) { console.error("saveConfig error:", err) }
                        )
                    }
                }

                Components.GlassButton {
                    objectName: "configReloadButton"
                    text: "Reload"
                    onClicked: root.loadConfig()
                }
            }

            // OAuth section
            Text {
                text: "OAuth"
                Accessible.name: "OAuth"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Text {
                text: "OAuth Authorization Code"
                Accessible.name: "OAuth Authorization Code"
                font.pixelSize: Theme.fontSmall
                color: Theme.textSecondary
            }

            Row {
                width: parent.width
                spacing: Theme.spacingSmall

                Components.SearchField {
                    id: oauthCodeField
                    objectName: "oauthCodeField"
                    width: parent.width - submitOAuthBtn.width - Theme.spacingSmall
                    placeholder: "Paste OAuth code..."
                }

                Components.GlassButton {
                    id: submitOAuthBtn
                    objectName: "submitOAuthButton"
                    text: "Submit"
                    filled: true
                    onClicked: {
                        controller.submitOAuthCode("", oauthCodeField.text,
                            function() { oauthCodeField.text = ""; console.log("OAuth code submitted") },
                            function(err) { console.warn("submitOAuthCode error:", err) }
                        )
                    }
                }
            }

            // System section
            Text {
                text: "System"
                Accessible.name: "System"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Row {
                spacing: Theme.spacingSmall

                Components.GlassButton {
                    objectName: "resetCacheButton"
                    text: "Reset Cache"
                    onClicked: controller.resetCache(function() { console.log("Cache reset") }, function(err) { console.warn("resetCache error:", err) })
                }

                Components.GlassButton {
                    objectName: "restartButton"
                    text: "Restart Backend"
                    accentColor: Theme.warning
                    onClicked: controller.restart(function() { console.log("Backend restarting") }, function(err) { console.warn("restart error:", err) })
                }
            }

            Text {
                text: "Logging Level"
                Accessible.name: "Logging Level"
                font.pixelSize: Theme.fontSmall
                color: Theme.textSecondary
                topPadding: Theme.spacingSmall
            }

            Row {
                spacing: Theme.spacingTiny
                Repeater {
                    model: [0, 1, 2, 3, 4, 5]
                    Components.GlassButton {
                        objectName: "loggingLevel" + modelData
                        text: modelData.toString()
                        width: 40
                        filled: root.loggingLevel === modelData
                        onClicked: {
                            controller.setLoggingLevel(modelData,
                                function() { root.loggingLevel = modelData },
                                function(err) { console.warn("setLoggingLevel error:", err) }
                            )
                        }
                    }
                }
            }

            // App Settings section
            Text {
                text: "App Settings"
                Accessible.name: "App Settings"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Text { text: "Preview RTMP URL"; Accessible.name: "Preview RTMP URL"; font.pixelSize: Theme.fontSmall; color: Theme.textSecondary }
            Components.SearchField {
                objectName: "previewRtmpUrlField"
                width: parent.width
                text: root.settings.previewRTMPUrl
                placeholder: "rtmp://..."
                onTextChanged: root.settings.previewRTMPUrl = text
            }

            Text { text: "Preview RTMP Port"; Accessible.name: "Preview RTMP Port"; font.pixelSize: Theme.fontSmall; color: Theme.textSecondary }
            Components.SearchField {
                objectName: "previewRtmpPortField"
                width: parent.width
                text: root.settings.previewRTMPPort
                placeholder: "1945"
                onTextChanged: root.settings.previewRTMPPort = text
            }

            Text { text: "Manual Input FPS"; Accessible.name: "Manual Input FPS"; font.pixelSize: Theme.fontSmall; color: Theme.textSecondary }
            Components.SearchField {
                objectName: "manualInputFpsField"
                width: parent.width
                text: root.settings.manualInputFPS
                placeholder: "Leave empty for auto"
                onTextChanged: root.settings.manualInputFPS = text
            }

            // App info
            Text {
                text: "About"
                Accessible.name: "About"
                font.pixelSize: Theme.fontLarge
                font.weight: Font.Medium
                color: Theme.textPrimary
                topPadding: Theme.spacingSmall
            }

            Components.GlassCard {
                width: parent.width
                implicitHeight: aboutCol.implicitHeight + Theme.spacingLarge * 2

                Column {
                    id: aboutCol
                    anchors.fill: parent
                    spacing: Theme.spacingTiny

                    Text {
                        text: "WingOut 2.0.0"
                        Accessible.name: "WingOut 2.0.0"
                        font.pixelSize: Theme.fontMedium
                        font.weight: Font.Bold
                        color: Theme.textPrimary
                    }
                    Text {
                        text: "IRL Streaming Application"
                        Accessible.name: "IRL Streaming Application"
                        font.pixelSize: Theme.fontSmall
                        color: Theme.textSecondary
                    }
                }
            }
        }
    }
}
