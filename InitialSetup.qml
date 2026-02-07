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
    width: 540
    height: 180
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
                    var val = setupHostField.text.trim();
                    if (val.length === 0) {
                        return;
                    }
                    // Ensure scheme is present; default to http:// if omitted
                    if (!val.startsWith("http://") && !val.startsWith("https://")) {
                        val = "http://" + val;
                    }
                    setupWindow.appSettings.dxProducerHost = val;
                    setupWindow.finished();
                    setupWindow.close();
                }
            }
        }
    }
}
