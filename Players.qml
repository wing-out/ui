/* This file implements the Players page for managing stream players. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: playersPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Players")
    padding: 12

    Component.onCompleted: {
        refreshPlayers();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Stream Players"; font.pixelSize: 20 }
            Item { Layout.fillWidth: true }
            Button { text: "Refresh"; onClicked: refreshPlayers() }
        }

        ListView {
            id: playersList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel { id: playersModel }
            delegate: Rectangle {
                width: parent.width
                height: 70
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
                        Label { text: playerID; font.pixelSize: 18; font.bold: true }
                        Label { text: "URI: " + uri; opacity: 0.7; font.pixelSize: 14; elide: Text.ElideRight }
                    }
                    
                    Button {
                        text: "Close"
                        palette.button: "darkred"
                        palette.buttonText: "white"
                        onClicked: {
                            console.log("Close player:", playerID);
                        }
                    }
                }
            }
        }
    }

    function refreshPlayers() {
        console.log("Players.qml: Requesting list of stream players...");
        
        dxProducerClient.listStreamPlayers(function(reply) {
            console.log("Players.qml: Received reply:", JSON.stringify(reply));
            playersModel.clear();
            var players = reply.playersData || reply.players || [];
            for (var i = 0; i < players.length; i++) {
                var p = players[i];
                playersModel.append({
                    playerID: p.streamSourceID,
                    uri: (p.streamPlaybackConfig && p.streamPlaybackConfig.overriddenURL) ? p.streamPlaybackConfig.overriddenURL : "default"
                });
            }
        }, function(error) { 
            console.log("Players.qml: Error listing stream players");
            processStreamDGRPCError(dxProducerClient, error); 
        }, grpcCallOptions);
    }
}
