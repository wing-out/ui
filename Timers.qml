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

    Timer {
        id: updateFFStreamLatenciesTicker
        interval: 200
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: updatePlayerLagTicker
        interval: 100
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: fetchPlayerLagTicker
        interval: 200
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: updateFFStreamInputQualityTicker
        interval: 200
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: updateFFStreamOutputQualityTicker
        interval: 200
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: updateFFStreamBitRatesTicker
        interval: 200
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
    property alias updateFFStreamLatenciesTicker: updateFFStreamLatenciesTicker
    property alias updatePlayerLagTicker: updatePlayerLagTicker
    property alias fetchPlayerLagTicker: fetchPlayerLagTicker
    property alias updateFFStreamInputQualityTicker: updateFFStreamInputQualityTicker
    property alias updateFFStreamOutputQualityTicker: updateFFStreamOutputQualityTicker
    property alias updateFFStreamBitRatesTicker: updateFFStreamBitRatesTicker
}
