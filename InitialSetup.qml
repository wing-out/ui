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
    width: Screen.width > 0 ? Math.min(540, Screen.width) : 540
    height: Screen.height > 0 ? Screen.height : 800
    visible: true

    signal finished()

    property var appSettings

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true

            ColumnLayout {
                width: scrollView.availableWidth
                spacing: 8

                Label {
                    text: qsTr("Enter StreamD server address (e.g. http://192.168.0.134:3594):")
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                TextField {
                    id: setupHostField
                    objectName: "setupHostField"
                    placeholderText: "http://host:port"
                    text: setupWindow.appSettings.dxProducerHost
                    Layout.fillWidth: true
                    focus: true
                }

                Label {
                    text: qsTr("Preview RTMP URL (leave blank to disable preview):")
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }

                TextField {
                    id: setupPreviewUrlField
                    placeholderText: "rtmp://host:port/app/stream"
                    text: setupWindow.appSettings.previewRTMPUrl
                    Layout.fillWidth: true
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
            }
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
                objectName: "saveButton"
                text: qsTr("Save")
                highlighted: true
                onClicked: {
                    Qt.inputMethod.commit();
                    var val = setupHostField.text.trim();
                    if (val.length === 0) {
                        return;
                    }
                    if (!val.startsWith("http://") && !val.startsWith("https://")) {
                        val = "https://" + val;
                    }
                    setupWindow.appSettings.dxProducerHost = val;
                    var previewUrl = setupPreviewUrlField.text.trim();
                    setupWindow.appSettings.previewRTMPUrl = previewUrl;
                    var ffstreamUrl = setupFFStreamField.text.trim();
                    setupWindow.appSettings.ffstreamHost = ffstreamUrl;
                    setupWindow.finished();
                    setupWindow.close();
                }
            }
        }
    }
}
