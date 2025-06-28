import QtQuick

Item {
    Timer {
        id: retryTimerDXProducerClientSubscribeToChatMessages
        interval: 1000 // 1 second
        repeat: false
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: retryTimerDXProducerClientSubscribeToScreenshot
        interval: 1000
        repeat: false
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: pingTicker
        interval: 200
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: streamStatusTicker
        interval: 1000
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    property alias retryTimerDXProducerClientSubscribeToChatMessages: retryTimerDXProducerClientSubscribeToChatMessages
    property alias retryTimerDXProducerClientSubscribeToScreenshot: retryTimerDXProducerClientSubscribeToScreenshot
    property alias pingTicker: pingTicker
    property alias streamStatusTicker: streamStatusTicker
}
