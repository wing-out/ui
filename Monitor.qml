/* This file implements the Monitor page for viewing incoming streams. */
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Page {
    id: monitorPage
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Monitor")

    property var streams: []
    property string activeStreamUrl: ""

    function refresh() {
        console.log("Monitor.qml: Requesting stream sources...");
        dxProducerClient.listStreamSources(function(response) {
            console.log("Monitor.qml: Received response:", JSON.stringify(response));
            monitorPage.streams = response.streamSourcesData || response.streamSources || [];
        }, function(error) { 
            console.log("Monitor.qml: Error listing stream sources");
            processStreamDGRPCError(dxProducerClient, error); 
        }, grpcCallOptions);
    }

    Component.onCompleted: refresh()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        Label {
            text: "Select a stream to monitor:"
            font.bold: true
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            model: monitorPage.streams
            clip: true
            delegate: ItemDelegate {
                width: parent.width
                text: modelData.streamSourceID
                onClicked: {
                    // This is a guess on the RTMP URL format
                    monitorPage.activeStreamUrl = "rtmp://localhost:1935/live/" + modelData.streamSourceID;
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "black"
            border.color: "gray"

            VideoPlayerRTMP {
                anchors.fill: parent
                source: monitorPage.activeStreamUrl
                visible: monitorPage.activeStreamUrl !== ""
            }

            Label {
                anchors.centerIn: parent
                text: "No stream selected"
                visible: monitorPage.activeStreamUrl === ""
                color: "white"
            }
        }

        Button {
            text: "Refresh Streams"
            onClicked: refresh()
        }
    }
}

