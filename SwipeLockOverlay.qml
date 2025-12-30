import QtQuick
import QtQuick.Controls

Popup {
    id: root

    property bool locked: false
    property real safeAreaTop: 0
    signal unlockRequested

    modal: true
    dim: false
    closePolicy: Popup.NoAutoClose
    focus: true

    parent: Overlay.overlay
    x: 0
    y: 0
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0

    property real handleTopMargin: 5 + safeAreaTop
    property real unlockThreshold: height * 0.5

    background: Rectangle {
        anchors.fill: parent
        color: "transparent"
        Keys.onPressed: function (event) {
            event.accepted = true;
        }
    }

    onLockedChanged: {
        if (locked && !opened)
            open();
        else if (!locked && opened)
            close();
    }

    Rectangle {
        id: handle
        width: 60
        height: 60
        radius: 30
        color: "#80ffffff"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.handleTopMargin

        DragHandler {
            id: drag
            target: handle
            xAxis.enabled: false
            yAxis.enabled: true
            yAxis.minimum: root.handleTopMargin
            yAxis.maximum: root.height - handle.height - root.handleTopMargin

            onActiveChanged: {
                if (!active) {
                    if (handle.y >= root.unlockThreshold) {
                        root.unlockRequested();
                    }
                    resetAnim.from = handle.y;
                    resetAnim.to = root.handleTopMargin;
                    resetAnim.restart();
                }
            }
        }

        NumberAnimation {
            id: resetAnim
            target: handle
            property: "y"
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Label {
        text: "Swipe down to unlock"
        anchors.centerIn: handle
        color: "white"
        font.pixelSize: 14
    }

    onOpened: {
        handle.y = handleTopMargin;
    }
}
