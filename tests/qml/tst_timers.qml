import QtQuick
import QtTest
import WingOut

/// Tests the Timers component – timer creation and callback invocation.
TestCase {
    id: tc
    name: "Timers"
    when: windowShown
    width: 100
    height: 100

    Component {
        id: timersComp
        Timers {}
    }

    function test_01_timers_create() {
        var t = createTemporaryObject(timersComp, tc)
        verify(t !== null, "Timers component should instantiate")
    }

    function test_02_all_timers_exist() {
        var t = createTemporaryObject(timersComp, tc)
        verify(t !== null)
        // Verify a representative set of timer aliases are present.
        verify(t.pingTicker !== undefined, "pingTicker should exist")
        verify(t.streamStatusTicker !== undefined, "streamStatusTicker should exist")
        verify(t.updateFFStreamLatenciesTicker !== undefined,
               "updateFFStreamLatenciesTicker should exist")
        verify(t.updateWiFiInfoTicker !== undefined,
               "updateWiFiInfoTicker should exist")
        verify(t.updateResourcesTicker !== undefined,
               "updateResourcesTicker should exist")
        verify(t.channelQualityInfoTicker !== undefined,
               "channelQualityInfoTicker should exist")
    }

    function test_03_callback_invoked() {
        var t = createTemporaryObject(timersComp, tc)
        verify(t !== null)

        var callCount = 0
        t.pingTicker.callback = function () { callCount++ }
        t.pingTicker.interval = 50
        t.pingTicker.repeat = true
        t.pingTicker.start()

        // Wait enough for at least 2 firings.
        wait(200)
        t.pingTicker.stop()
        verify(callCount >= 2,
               "Callback should have fired at least twice, got " + callCount)
    }

    function test_04_timer_default_intervals() {
        var t = createTemporaryObject(timersComp, tc)
        verify(t !== null)
        compare(t.pingTicker.interval, 200, "Ping interval should be 200ms")
        compare(t.streamStatusTicker.interval, 1000,
                "StreamStatus interval should be 1000ms")
    }
}
