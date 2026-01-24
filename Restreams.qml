/* This file implements the Restreams page for managing stream forwards. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: restreamsPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Restreams")
    padding: 12

    Component.onCompleted: {
        refreshRestreams();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Restreams"; font.pixelSize: 20 }
            Item { Layout.fillWidth: true }
            Button { text: "Refresh"; onClicked: refreshRestreams() }
            Button { text: "New" }
        }

        ListView {
            id: restreamsList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel { id: restreamsModel }
            delegate: Rectangle {
                width: parent.width
                height: 80
                color: "#222"
                border.color: "#444"
                radius: 6
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label { text: streamSourceID; font.pixelSize: 18; font.bold: true }
                        Label { text: "To: " + streamSinkID; opacity: 0.7; font.pixelSize: 14 }
                        Label { 
                            text: enabled ? "Status: Active" : "Status: Paused"
                            color: enabled ? "lightgreen" : "orange"
                            font.pixelSize: 12
                        }
                    }
                    
                    Button {
                        text: enabled ? "Stop" : "Start"
                        palette.button: enabled ? "red" : "green"
                        palette.buttonText: "white"
                        onClicked: {
                            // TODO: implement toggle
                            console.log("Toggle restream:", streamSourceID);
                        }
                    }
                }
            }
        }
    }

    function refreshRestreams() {
        console.log("Restreams.qml: Requesting stream forwards...");
        
        dxProducerClient.listStreamForwards(function(reply) {
            console.log("Restreams.qml: Received reply:", JSON.stringify(reply));
            restreamsModel.clear();
            var forwards = reply.streamForwardsData || reply.streamForwards || [];
            for (var i = 0; i < forwards.length; i++) {
                var f = forwards[i].config;
                restreamsModel.append({
                    streamSourceID: f.streamSourceID,
                    streamSinkID: f.streamSinkID,
                    enabled: f.enabled
                });
            }
        }, function(error) { 
            console.log("Restreams.qml: Error listing stream forwards");
            processStreamDGRPCError(dxProducerClient, error); 
        }, grpcCallOptions);
    }
}
