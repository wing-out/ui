pragma ComponentBehavior: Bound
/* This file implements the Settings page for app configuration. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: settingsPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Settings")
    padding: 0

    property string configText: ""

    function refresh() {
        console.log("Settings.qml: Requesting config...");
        if (!main.checkStreamDClient()) {
            return;
        }
        main.dxProducerClient.getConfig(function (response) {
            console.log("Settings.qml: Received config response");
            settingsPage.configText = response.config || "";
        }, function (error) {
            console.log("Settings.qml: Error getting config");
            main.processStreamDGRPCError(main.dxProducerClient, error);
        }, main.grpcCallOptions);
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TabBar {
            id: settingsBar
            Layout.fillWidth: true
            TabButton {
                text: "Editor"
            }
            TabButton {
                text: "OAuth"
            }
            TabButton {
                text: "System"
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: settingsBar.currentIndex

            // Editor Tab
            ColumnLayout {
                spacing: 8
                Layout.margins: 10

                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: "Refresh"
                        onClicked: refresh()
                    }
                    Button {
                        text: "Save"
                        highlighted: true
                        onClicked: {
                            console.log("Settings.qml: Saving config...");
                            if (!main.checkStreamDClient()) {
                                return;
                            }
                            main.dxProducerClient.setConfig(settingsPage.configText, function (response) {
                                console.log("Settings.qml: Config saved successfully");
                                refresh();
                            }, function (error) {
                                console.log("Settings.qml: Error saving config");
                                main.processStreamDGRPCError(main.dxProducerClient, error);
                            }, main.grpcCallOptions);
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    TextArea {
                        text: settingsPage.configText
                        font.family: "Monospace"
                        wrapMode: TextEdit.Wrap
                        onTextChanged: settingsPage.configText = text
                        background: Rectangle {
                            color: "#1a1a1a"
                            border.color: "#333"
                        }
                    }
                }
            }

            // OAuth Tab
            ColumnLayout {
                spacing: 20
                Layout.margins: 20

                Label {
                    text: "Submit OAuth Code"
                    font.bold: true
                    font.pixelSize: 18
                }

                TextField {
                    id: oauthCodeField
                    placeholderText: "Paste code here..."
                    Layout.fillWidth: true
                }

                Button {
                    text: "SUBMIT CODE"
                    Layout.fillWidth: true
                    onClicked: {
                        if (!main.checkStreamDClient()) {
                            return;
                        }
                        // Keep {} for SubmitOAuthCode because it's NOT overridden in dx_producer_client.cpp
                        main.dxProducerClient.SubmitOAuthCode({
                            code: oauthCodeField.text
                        }, function () {
                            oauthCodeField.text = "";
                            console.log("OAuth code submitted");
                        }, function (error) {
                            main.processStreamDGRPCError(main.dxProducerClient, error);
                        }, main.grpcCallOptions);
                    }
                }

                Item {
                    Layout.fillHeight: true
                }
            }

            // System Tab
            ColumnLayout {
                spacing: 20
                Layout.margins: 20

                Label {
                    text: "System Actions"
                    font.bold: true
                    font.pixelSize: 18
                }

                Button {
                    text: "Reset Cache"
                    Layout.fillWidth: true
                    // Keep {} for ResetCache because it's NOT overridden
                    onClicked: {
                        if (!main.checkStreamDClient()) {
                            return;
                        }
                        main.dxProducerClient.ResetCache({}, function () {
                            console.log("Cache reset");
                        }, function (e) {
                            main.processStreamDGRPCError(main.dxProducerClient, e);
                        }, main.grpcCallOptions);
                    }
                }


                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }
}
