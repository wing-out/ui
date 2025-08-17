//import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
//import Qt.labs.folderlistmodel

Page {
    id: application
    Material.theme: Material.Dark
    Material.accent: Material.Purple
    title: qsTr("Settings")

    /*
    FolderListModel {
        id: resourceModel
        folder: "qrc:/qt/qml/WingOut/fonts"
        nameFilters: ["*"]
    }

    ListView {
        anchors.fill: parent
        model: resourceModel
        delegate: Text {
            text: fileName
            color: '#ffffff'
        }
    }
    */
}
