pragma ComponentBehavior: Bound
/* This file implements the Profiles page for managing and starting/stopping stream profiles via gRPC. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: profilesPage
    required property var root
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Profiles")
    padding: 0

    QtObject {
        id: llmState
        property bool generating: false
        property string generatedTitle: ""
        property string statusText: ""
        property color statusColor: "#808080"
    }

    Component.onCompleted: {
        refreshProfiles();
    }

    StackLayout {
        id: profileStack
        anchors.fill: parent
        currentIndex: 0

        // Screen 0: List of Profiles
        ColumnLayout {
            spacing: 0
            
            ToolBar {
                Layout.fillWidth: true
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    Label {
                        text: "Stream Profiles"
                        font.pixelSize: 20
                        Layout.fillWidth: true
                    }
                    ToolButton { text: "🔄"; onClicked: refreshProfiles() }
                    ToolButton { text: "➕"; onClicked: newProfileDialog.open() }
                }
            }

            ListView {
                id: profilesList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: []
                clip: true
                delegate: ItemDelegate {
                    width: parent.width
                    text: modelData
                    highlighted: ListView.isCurrentItem
                    onClicked: {
                        profilesList.currentIndex = index;
                        profileNameField.text = modelData;
                        profileStack.currentIndex = 1; // Go to detail
                    }
                }
            }
        }

        // Screen 1: Profile Details
        ColumnLayout {
            spacing: 0
            
            ToolBar {
                Layout.fillWidth: true
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    ToolButton {
                        text: "⬅️"
                        onClicked: profileStack.currentIndex = 0
                    }
                    Label {
                        text: profileNameField.text || "Profile Detail"
                        font.pixelSize: 20
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                
                ColumnLayout {
                    width: parent.width
                    spacing: 16
                    anchors.margins: 16
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Title"; opacity: 0.6; font.pixelSize: 12 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField { id: profileTitleField; placeholderText: "Stream title"; Layout.fillWidth: true }
                            Button {
                                id: generateTitleBtn
                                text: "AI"
                                font.pixelSize: 12
                                enabled: !llmState.generating
                                ToolTip.visible: hovered
                                ToolTip.text: "Generate title with LLM"
                                onClicked: {
                                    llmState.generating = true;
                                    llmState.statusText = "Generating...";
                                    llmState.statusColor = "#FFFF00";
                                    dxProducerClient.llmGenerate(
                                        "Generate a catchy stream title for an IRL stream. Reply with just the title, nothing else.",
                                        function(reply) {
                                            llmState.generating = false;
                                            var generated = reply.response || "";
                                            if (generated.length > 0) {
                                                llmState.generatedTitle = generated;
                                                llmState.statusText = "Generated! Tap Apply to use.";
                                                llmState.statusColor = "#00FF00";
                                            } else {
                                                llmState.statusText = "Empty response";
                                                llmState.statusColor = "#FF0000";
                                            }
                                        },
                                        function(error) {
                                            llmState.generating = false;
                                            llmState.statusText = "Generation failed";
                                            llmState.statusColor = "#FF0000";
                                            console.warn("LLM generate failed:", error);
                                            processStreamDGRPCError(dxProducerClient, error);
                                        },
                                        grpcCallOptions);
                                }
                            }
                        }

                        // LLM generation result area
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            visible: llmState.generatedTitle.length > 0 || llmState.statusText.length > 0

                            Label {
                                text: llmState.statusText
                                color: llmState.statusColor
                                font.pixelSize: 11
                                visible: llmState.statusText.length > 0
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                visible: llmState.generatedTitle.length > 0

                                Label {
                                    Layout.fillWidth: true
                                    text: llmState.generatedTitle
                                    wrapMode: Text.Wrap
                                    font.pixelSize: 13
                                    font.italic: true
                                    color: "#AAAAFF"
                                }

                                Button {
                                    text: "Apply"
                                    font.pixelSize: 11
                                    onClicked: {
                                        profileTitleField.text = llmState.generatedTitle;
                                        llmState.generatedTitle = "";
                                        llmState.statusText = "";
                                    }
                                }

                                Button {
                                    text: "Set All"
                                    font.pixelSize: 11
                                    ToolTip.visible: hovered
                                    ToolTip.text: "Apply title to all platforms"
                                    onClicked: {
                                        var title = llmState.generatedTitle;
                                        profileTitleField.text = title;
                                        llmState.generatedTitle = "";
                                        fireMultiPlatformRPC("Title",
                                            function(platID, onOk, onErr) { dxProducerClient.setTitle(platID, title, onOk, onErr, grpcCallOptions); },
                                            function(t) { llmState.statusText = t; },
                                            function(c) { llmState.statusColor = c; });
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Description"; opacity: 0.6; font.pixelSize: 12 }
                        TextArea { id: profileDescField; placeholderText: "Stream description"; Layout.fillWidth: true; wrapMode: TextEdit.Wrap; implicitHeight: 100 }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Label { text: "Profile Identifier"; opacity: 0.6; font.pixelSize: 12 }
                        TextField { id: profileNameField; placeholderText: "Profile name"; Layout.fillWidth: true; readOnly: true; color: "gray" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Button {
                             text: "START STREAM"
                             Layout.fillWidth: true
                             onClicked: startClicked()
                             palette.button: "green"
                             palette.buttonText: "white"
                             font.bold: true
                        }
                        Button {
                             text: "STOP"
                             Layout.fillWidth: true
                             onClicked: stopClicked()
                             palette.button: "red"
                             palette.buttonText: "white"
                             font.bold: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Button { text: "Clone"; onClicked: cloneProfileDialog.open() }
                        Button { text: "Delete"; palette.buttonText: "red"; onClicked: deleteProfileDialog.open() }
                        Item { Layout.fillWidth: true }
                    }
                    
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // dialogs
    Dialog {
        id: newProfileDialog
        title: "New profile"
        standardButtons: Dialog.Ok | Dialog.Cancel
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true
        width: 300
        contentItem: ColumnLayout {
            spacing: 8
            TextField { placeholderText: "Profile name"; Layout.fillWidth: true }
        }
    }

    Dialog {
        id: cloneProfileDialog
        title: "Clone profile"
        standardButtons: Dialog.Ok | Dialog.Cancel
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true
        width: 300
        contentItem: ColumnLayout {
            spacing: 8
            TextField { placeholderText: "New profile name"; Layout.fillWidth: true }
        }
    }

    Dialog {
        id: deleteProfileDialog
        title: "Delete profile"
        standardButtons: Dialog.Ok | Dialog.Cancel
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true
        width: 300
        contentItem: ColumnLayout {
            spacing: 8
            Label { text: "Are you sure you want to delete this profile?" }
        }
    }

    function refreshProfiles() {
        console.log("Profiles.qml: Requesting list of profiles...");
        if (!profilesPage.root.checkStreamDClient()) {
            return;
        }
        profilesPage.root.dxProducerClient.listProfiles(function(reply) {
            console.log("Profiles.qml: Received reply:", JSON.stringify(reply));
            var names = [];
            var profiles = reply.profilesData || reply.profiles;
            if (reply && profiles) {
                for (var i = 0; i < profiles.length; i++) {
                    var p = profiles[i];
                    console.log("Profiles.qml: Adding profile:", p.name);
                    names.push(p.name);
                }
            }
            profilesList.model = names;
        }, function(error) {
            console.log("Profiles.qml: Error listing profiles");
            profilesPage.root.processStreamDGRPCError(profilesPage.root.dxProducerClient, error);
        }, profilesPage.root.grpcCallOptions);
    }

    function startClicked() {
        if (!profilesPage.root.checkStreamDClient()) {
            return;
        }
        var platIDs = ["twitch", "youtube", "kick"];
        for (var i = 0; i < platIDs.length; i++) {
            profilesPage.root.dxProducerClient.startStream(platIDs[i], profileNameField.text, function() {
                console.log("Profiles.qml: Started stream on success");
            }, function(error) {
                console.log("Profiles.qml: Error starting stream");
                profilesPage.root.processStreamDGRPCError(profilesPage.root.dxProducerClient, error);
            }, profilesPage.root.grpcCallOptions);
        }
    }

    function stopClicked() {
        if (!profilesPage.root.checkStreamDClient()) {
            return;
        }
        var platIDs = ["twitch", "youtube", "kick"];
        for (var i = 0; i < platIDs.length; i++) {
            profilesPage.root.dxProducerClient.endStream(platIDs[i], function() {
                console.log("Profiles.qml: Stopped stream success");
            }, function(error) {
                console.log("Profiles.qml: Error stopping stream");
                profilesPage.root.processStreamDGRPCError(profilesPage.root.dxProducerClient, error);
            }, profilesPage.root.grpcCallOptions);
        }
    }
}
