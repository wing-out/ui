/* This file implements Timers used for retries and periodic tasks. */
import QtQuick

Item {
    Timer {
        id: retryTimerSubscribeToChatMessages
        interval: 1000 // 1 second
        repeat: false
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: retryTimerSubscribeToScreenshot
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

    Timer {
        id: updateWiFiInfoTicker
        interval: 1000
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }

    Timer {
        id: channelQualityInfoTicker
        interval: 1000
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }
    Timer {
        id: updateResourcesTicker
        interval: 1000
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }
    Timer {
        id: injectDiagnosticsSubtitlesTicker
        interval: 1000
        repeat: true
        property var callback: null
        onTriggered: {
            callback()
        }
    }
    property alias retryTimerSubscribeToChatMessages: retryTimerSubscribeToChatMessages
    property alias retryTimerSubscribeToScreenshot: retryTimerSubscribeToScreenshot
    property alias pingTicker: pingTicker
    property alias streamStatusTicker: streamStatusTicker
    property alias updateFFStreamLatenciesTicker: updateFFStreamLatenciesTicker
    property alias updatePlayerLagTicker: updatePlayerLagTicker
    property alias fetchPlayerLagTicker: fetchPlayerLagTicker
    property alias updateFFStreamInputQualityTicker: updateFFStreamInputQualityTicker
    property alias updateFFStreamOutputQualityTicker: updateFFStreamOutputQualityTicker
    property alias updateFFStreamBitRatesTicker: updateFFStreamBitRatesTicker
    property alias updateWiFiInfoTicker: updateWiFiInfoTicker
    property alias channelQualityInfoTicker: channelQualityInfoTicker
    property alias updateResourcesTicker: updateResourcesTicker
}
