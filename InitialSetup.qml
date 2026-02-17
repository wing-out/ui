pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

Window {
    id: setupWindow
    title: qsTr("Setup StreamD host")
    modality: Qt.ApplicationModal
    flags: Qt.Dialog
    // Constrain to screen size: at 420 DPI the screen is only
    // ~411dp wide, so a fixed 540dp Window overflows and pushes
    // buttons off the right edge.
    width: Screen.width > 0 ? Math.min(540, Screen.width) : 540
    height: Screen.height > 0 ? Math.min(180, Screen.height) : 180
    visible: true

    signal finished()

    property var appSettings

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Label {
            text: qsTr("Enter StreamD server address (e.g. http://192.168.0.134:3594):")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        TextField {
            id: setupHostField
            placeholderText: "http://host:port"
            text: setupWindow.appSettings.dxProducerHost
            Layout.fillWidth: true
            focus: true
        }

        Label {
            text: qsTr("Preview RTMP (optional override):")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        TextField {
            id: setupPreviewUrlField
            placeholderText: "rtmp://host:port/app/stream"
            text: setupWindow.appSettings.previewRTMPUrl
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: setupPreviewPortField
                placeholderText: "RTMP port (default 1945)"
                text: setupWindow.appSettings.previewRTMPPort
                Layout.fillWidth: true
                Layout.preferredWidth: 140
                inputMethodHints: Qt.ImhDigitsOnly
            }

            TextField {
                id: setupPreviewStreamField
                placeholderText: "Stream ID (default pixel/dji-osmo-pocket-3-merged/)"
                text: setupWindow.appSettings.previewRTMPStreamID
                Layout.fillWidth: true
            }
        }

        Label {
            text: qsTr("Enter FFStream gRPC host (optional, e.g. https://127.0.0.1:3593):")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        TextField {
            id: setupFFStreamField
            placeholderText: "https://127.0.0.1:3593"
            text: setupWindow.appSettings.ffstreamHost
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                text: qsTr("Cancel")
                onClicked: {
                    Qt.quit();
                }
            }

            Button {
                text: qsTr("Save")
                highlighted: true
                onClicked: {
                    // Force the IME to commit any composing text
                    // (e.g., from adb shell input text) before reading
                    // the property, otherwise TextField.text may be
                    // empty while the field visually shows the URL.
                    Qt.inputMethod.commit();
                    var val = setupHostField.text.trim();
                    if (val.length === 0) {
                        return;
                    }
                    // Ensure scheme is present; default to https:// if omitted
                    if (!val.startsWith("http://") && !val.startsWith("https://")) {
                        val = "https://" + val;
                    }
                    setupWindow.appSettings.dxProducerHost = val;
                    var previewUrl = setupPreviewUrlField.text.trim();
                    var previewPort = setupPreviewPortField.text.trim();
                    var previewStream = setupPreviewStreamField.text.trim();
                    if (previewUrl.length === 0 && previewPort.length === 0 && previewStream.length === 0) {
                        previewPort = "1945";
                        previewStream = "pixel/dji-osmo-pocket-3-merged/";
                    }
                    setupWindow.appSettings.previewRTMPUrl = previewUrl;
                    setupWindow.appSettings.previewRTMPPort = previewPort.length > 0 ? previewPort : "";
                    setupWindow.appSettings.previewRTMPStreamID = previewStream.length > 0 ? previewStream : "";
                    var ffstreamUrl = setupFFStreamField.text.trim();
                    if (ffstreamUrl.length > 0) {
                        setupWindow.appSettings.ffstreamHost = ffstreamUrl;
                    } else {
                        setupWindow.appSettings.ffstreamHost = "";
                    }
                    setupWindow.finished();
                    setupWindow.close();
                }
            }
        }
    }
}
