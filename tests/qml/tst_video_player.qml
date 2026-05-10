import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Tests the VideoPlayerRTMP component in isolation (no actual RTMP stream).
TestCase {
    id: tc
    name: "VideoPlayerRTMP"
    when: windowShown
    width: 540
    height: 300

    Component {
        id: playerComp
        VideoPlayerRTMP {
            width: 320
            height: 240
        }
    }

    function test_01_creates() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null, "VideoPlayerRTMP should instantiate")
    }

    function test_02_default_muted() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null)
        verify(p.audioMuted === true, "Audio should be muted by default")
    }

    function test_03_stream_name_property() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null)
        p.streamName = "test-stream"
        compare(p.streamName, "test-stream", "streamName should be settable")
    }

    // ============================================================
    // T-1.2 — VideoPlayerRTMP retry timer no-ops on empty source
    // (consumer side of the empty-URL flow per Phase-4 spec
    // /tmp/claude-plans/task6-phase4-specs.md v3.2.2 Section 3 T-1.2).
    //
    // The empty-source guard at VideoPlayerRTMP.qml:228-239 (HEAD
    // 0205627; previously L228-L233 at HEAD fe22148 with the broken
    // QUrl-vs-string `=== ""` semantics — Task #22 fixed it via
    // `String(mediaPlayer.source || "").trim()` coercion + length
    // check) is the load-bearing line that prevents an empty-URL
    // retry storm. With the cleanup making empty-URL the DEFAULT
    // (not an edge case), removing this guard would cause RTMP
    // setSource("") calls every 100ms.
    //
    // retryTimer has no objectName — we walk the children tree by
    // Timer-with-interval-100 + repeat signature.
    // ============================================================
    function _findRetryTimer(node) {
        if (!node) return null
        // Timer at VideoPlayerRTMP.qml:207-249 has interval=100,
        // repeat=true, triggeredOnStart=true. statusLogTimer (interval
        // 500) and steadyStatusLogTimer (interval 1500) differ — the
        // 100ms repeating one is unique.
        if (node.interval !== undefined && node.interval === 100
                && node.repeat === true) {
            return node
        }
        // Timer is a non-visual QObject — only `data` (default property
        // for Item) contains it; `children` is filtered to visual items.
        // Walk both for completeness.
        var pool = []
        if (node.data) {
            for (var k = 0; k < node.data.length; k++) pool.push(node.data[k])
        }
        var children = node.children || []
        for (var c = 0; c < children.length; c++) pool.push(children[c])
        for (var i = 0; i < pool.length; i++) {
            var hit = _findRetryTimer(pool[i])
            if (hit) return hit
        }
        return null
    }

    function test_T_1_2_retry_timer_no_ops_on_empty_source() {
        var p = createTemporaryObject(playerComp, tc)
        verify(p !== null)
        // Force empty source explicitly — the alias on VideoPlayerRTMP
        // initialises mediaPlayer.source = "" by default.
        p.source = ""
        wait(50)

        var retryTimer = _findRetryTimer(p)
        verify(retryTimer !== null,
               "retryTimer (interval=100, repeat=true) must be findable")

        // ASSERTION 1 — Good IS: retry timer is alive (per spec
        // assertion 1).
        wait(150)
        verify(retryTimer.running,
               "retryTimer must be running after first 150ms")

        // Reset baselines for deterministic comparison; the C++
        // MediaPlayer may have bumped lastRestartAt during initial
        // loading attempts (mediaStatus transitions etc.). Once
        // lastRestartAt > 0 the backoff-guard at L225 dominates and
        // may further mask the empty-source guard we want to verify,
        // so reset just before the test window.
        p.mediaPlayer.lastRestartAt = 0
        var beforeRestart = p.mediaPlayer.lastRestartAt

        // ≥ 5 retry-timer ticks at 100ms interval (mandatory per spec
        // "After wait(500) (≥ 4 retry-timer ticks at 100ms interval)").
        wait(500)

        // ASSERTION 2/3 — Bad NOT: lastRestartAt remains 0. This is
        // the proxy for "no spurious setSource invocation while source
        // is empty" — the retry-timer body at VideoPlayerRTMP.qml:235
        // bumps lastRestartAt when it runs; if the empty-source guard
        // at L228-L233 short-circuited correctly, the body never runs
        // and lastRestartAt stays at the reset value (0).
        //
        // Spec assertion 2 (spy on mediaPlayer.setSource calls,
        // setSourceCallCount === 0) is INFEASIBLE without monkey-
        // patching mediaPlayer.setSource — which is a C++ Q_INVOKABLE
        // method on Qt's MediaPlayer, not redefinable from QML JS.
        // Per testing-discipline "Infeasible tests → document why +
        // provide alternative verification", we use lastRestartAt as
        // the alternative proxy: lastRestartAt is set on the same
        // body line that calls setSource (VideoPlayerRTMP.qml:235-241
        // — `lastRestartAt = now` immediately precedes
        // `setSource("")` and `setSource(source)`), so
        // `lastRestartAt === 0` is sufficient evidence that
        // setSource was never called from the retry-timer body.
        // [T1: testing-discipline skill loaded this session, high]
        //
        // Spec assertion 4 (when source becomes non-empty, body fires)
        // is INFEASIBLE in a deterministic headless environment: the
        // body's outer guard at L220 short-circuits while
        // mediaStatus === LoadingMedia AND (now - lastProgressAt <
        // 1000ms), which is exactly the state Qt's MediaPlayer
        // transitions to when source is set to a non-resolvable URL
        // — and the time to transition out of LoadingMedia depends on
        // the platform's RTMP probe timeout (variable). Testing-
        // discipline's "Write deterministic tests only" rule rejects
        // a wait-for-RTMP-fail dependency. The complementary "non-
        // empty source activates" contract is covered deterministically
        // by T-2.3 (Dashboard bindings activate when drivers are
        // non-empty), so coverage is preserved.
        compare(p.mediaPlayer.lastRestartAt, beforeRestart,
                "with empty source, the retry-timer body must not bump "
                + "lastRestartAt (empty-source guard at "
                + "VideoPlayerRTMP.qml:228-233 holds); "
                + "got: " + p.mediaPlayer.lastRestartAt
                + " (baseline: " + beforeRestart + "); source=\""
                + String(p.mediaPlayer.source || "") + "\"")
    }
}
