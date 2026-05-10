import QtQuick
import QtQuick.Controls
import QtTest
import WingOut

/// Phase-4 test suite: Main.qml Component.onCompleted conditional seed
/// (Section 5 in /tmp/claude-plans/task6-phase4-specs.md v3.2.2).
///
/// Pins the post-cleanup conditional seed at Main.qml:704-715 (HEAD
/// fe22148):
///
///   Component.onCompleted: {
///       ...
///       if (appSettings && (!appSettings.previewRTMPUrl
///                           || appSettings.previewRTMPUrl.length === 0)) {
///           var seed = defaultPreviewRtmpUrl();
///           if (seed && seed.length > 0) {
///               appSettings.previewRTMPUrl = seed;
///               console.log("Main.qml: seeded default previewRTMPUrl:",
///                           appSettings.previewRTMPUrl);
///           }
///       }
///   }
///
/// Two guards:
///   - Outer (L708): only seed when previewRTMPUrl is empty.
///   - Inner (L710): only write + log when seed is non-empty
///     (the cleanup of the unconditional `console.log` from the
///     pre-cleanup baseline).
TestCase {
    id: tc
    name: "MainOnCompletedSeed"
    when: windowShown
    width: 540
    height: 960

    Component {
        id: appSettingsStub
        QtObject {
            property string dxProducerHost: ""
            property string previewRTMPUrl: ""
            property string ffstreamHost: ""
        }
    }

    Component {
        id: platformStub
        QtObject {
            function refreshWiFiState() {}
        }
    }

    // Default Main wraps the production defaultPreviewRtmpUrl() (returns
    // "" at HEAD). Used by T-3.1 + T-3.3.
    Component {
        id: mainComponent
        Main {
            platformInstance: platformStub.createObject(tc)
            appSettings: appSettingsStub.createObject(tc)
        }
    }

    // T-3.2 wrapper: subclasses Main and overrides defaultPreviewRtmpUrl
    // to return a non-empty seed BEFORE Component.onCompleted runs. This
    // is the test-only override path for verifying the
    // conditional-seed-takes-effect branch (per coordinator Dispute 2
    // ruling: wrapper-component is the mandated primary path).
    //
    // Qt version pin: tested against Qt 6.10.1 (project default at
    // submission time). If wrapper-shadow semantics change in a future
    // Qt minor, re-evaluate the monkey-patch fallback (spec section 5
    // T-3.2 setup paragraph).
    Component {
        id: mainSeededComponent
        Main {
            platformInstance: platformStub.createObject(tc)
            appSettings: appSettingsStub.createObject(tc)
            // Override shadows the base-class function via QML lexical
            // scope. Component.onCompleted (Main.qml:704) resolves
            // defaultPreviewRtmpUrl() to this override, not the empty
            // base. [T1: QtDeclarative QML object hierarchy spec, high]
            function defaultPreviewRtmpUrl() {
                return "rtmp://192.0.2.10:1945/live/example-merged/"
            }
        }
    }

    // ---- Log-capture infeasibility note ----
    //
    // The spec's T-3.1 / T-3.2 assertions reference capturing
    // `console.log` to assert the seed-success line ("seeded default
    // previewRTMPUrl:") DID or did NOT fire. In Qt 6 QML, `console` is
    // a V4-runtime builtin and `console.log = function() {}` does not
    // reliably shim production code's `console.log` calls (the shim
    // attempted in v3.2 of this file did not capture Main.qml's seed
    // log line, while the seed itself wrote correctly — verified via
    // the previewRTMPUrlChanged signal counter). Per testing-discipline
    // "Infeasible tests → document why + provide alternative
    // verification", we use the previewRTMPUrlChanged SignalSpy as the
    // direct witness for whether the seed branch fired. The signal
    // emits exactly when `appSettings.previewRTMPUrl = seed` runs at
    // Main.qml:711 — i.e. the same source line that the log line at
    // Main.qml:712 documents. A pass on the signal-count assertion
    // therefore proves the seed code path did/did-not run, which is
    // the underlying contract; the log line is a side-effect of the
    // write, not a separate contract.
    //
    // Stronger alternative (intentionally NOT used): qInstallMessageHandler
    // in tst_wingout.cpp test setup. Rejected because (a) it requires
    // editing shared test infrastructure (file ownership boundary —
    // the shared C++ test setup is owned by the executor pair that
    // wrote it, not test-executor-1); (b) the previewRTMPUrlChanged
    // signal is a stronger witness anyway because it asserts the
    // STATE CHANGE, not the LOG SIDE-EFFECT.
    //
    // [T1: testing-discipline skill loaded this session; "Infeasible
    // tests → document why + provide alternative verification", high]

    // ============================================================
    // T-3.1 — Conditional seed does NOT write previewRTMPUrl when seed
    // is empty (the post-cleanup contract).
    // ============================================================
    function test_T_3_1_no_write_when_seed_empty() {
        var settings = createTemporaryObject(appSettingsStub, tc, {
            dxProducerHost: "https://198.51.100.10:3594",
            previewRTMPUrl: ""
        })
        var spy = Qt.createQmlObject(
            'import QtTest; SignalSpy { signalName: "previewRTMPUrlChanged" }',
            tc)
        spy.target = settings
        verify(spy.valid, "previewRTMPUrlChanged signal must exist on stub")

        var main = createTemporaryObject(mainComponent, tc, {
            appSettings: settings
        })
        verify(main !== null, "Main must instantiate")
        wait(150)  // Component.onCompleted budget

        // Assertion 1 — Good IS: seed branch did not fire.
        compare(settings.previewRTMPUrl, "",
                "previewRTMPUrl must remain \"\" when seed is empty")

        // Assertion 2 — Bad NOT: no signal emission, i.e. the seed
        // write line at Main.qml:711 did NOT execute. This is the
        // direct witness for the inner-guard short-circuit (alternative
        // to the infeasible console.log capture — see file header).
        compare(spy.count, 0,
                "previewRTMPUrlChanged spy must be 0 (no write happened)")

        // Assertion 3 — Bad NOT: legacy stem not seeded.
        verify(settings.previewRTMPUrl.indexOf("dji-osmo-pocket") === -1,
               "no legacy stem may appear in previewRTMPUrl")
    }

    // ============================================================
    // T-3.2 — Conditional seed DOES write previewRTMPUrl when seed is
    // non-empty (forward-compatibility for future deployments that
    // re-introduce a seed via wrapper-component override).
    //
    // Wrapper-component primary path per coordinator Dispute 2 ruling.
    // ============================================================
    function test_T_3_2_writes_when_seed_nonempty() {
        var settings = createTemporaryObject(appSettingsStub, tc, {
            dxProducerHost: "https://198.51.100.10:3594",
            previewRTMPUrl: ""
        })
        var spy = Qt.createQmlObject(
            'import QtTest; SignalSpy { signalName: "previewRTMPUrlChanged" }',
            tc)
        spy.target = settings
        verify(spy.valid)

        var main = createTemporaryObject(mainSeededComponent, tc, {
            appSettings: settings
        })
        verify(main !== null, "Main wrapper must instantiate")
        wait(150)

        // Assertion 1 — Good IS: when seed is non-empty, the write fires.
        compare(settings.previewRTMPUrl,
                "rtmp://192.0.2.10:1945/live/example-merged/",
                "previewRTMPUrl must be seeded with the non-empty seed")

        // Assertion 2 — Good IS: exactly one write (this is the direct
        // witness for the seed-success branch; subsumes the spec's
        // "log line fires" assertion under the infeasibility note —
        // see file header. spy.count == 1 proves Main.qml:711 ran
        // exactly once, which is the underlying contract).
        compare(spy.count, 1,
                "previewRTMPUrlChanged signal fires exactly once "
                + "(direct witness of Main.qml:711 seed-write)")
    }

    // ============================================================
    // T-3.3 — Conditional seed does NOT overwrite an existing non-empty
    // previewRTMPUrl (the OUTER guard at Main.qml:708).
    //
    // Parametric: tested with both the empty-seed (mainComponent) and
    // the non-empty-seed (mainSeededComponent) variants. In both cases
    // the user-configured value must survive Component.onCompleted.
    // ============================================================
    function test_T_3_3_does_not_overwrite_existing_value() {
        // -- Variant A: empty-seed (default Main, defaultPreviewRtmpUrl
        //    returns "") --
        var settingsA = createTemporaryObject(appSettingsStub, tc, {
            dxProducerHost: "https://198.51.100.10:3594",
            previewRTMPUrl: "rtmp://203.0.113.7/userconfig/"
        })
        var spyA = Qt.createQmlObject(
            'import QtTest; SignalSpy { signalName: "previewRTMPUrlChanged" }',
            tc)
        spyA.target = settingsA
        verify(spyA.valid)

        var mainA = createTemporaryObject(mainComponent, tc, {
            appSettings: settingsA
        })
        verify(mainA !== null)
        wait(150)

        // Assertion 1 — Good IS: outer guard short-circuited.
        compare(settingsA.previewRTMPUrl, "rtmp://203.0.113.7/userconfig/",
                "Variant A: user config must survive (empty seed)")
        // Assertion 3a — Bad NOT: no overwrite signal.
        compare(spyA.count, 0,
                "Variant A: previewRTMPUrlChanged spy must remain 0")

        // -- Variant B: non-empty-seed (wrapper) --
        var settingsB = createTemporaryObject(appSettingsStub, tc, {
            dxProducerHost: "https://198.51.100.10:3594",
            previewRTMPUrl: "rtmp://203.0.113.7/userconfig/"
        })
        var spyB = Qt.createQmlObject(
            'import QtTest; SignalSpy { signalName: "previewRTMPUrlChanged" }',
            tc)
        spyB.target = settingsB
        verify(spyB.valid)

        var mainB = createTemporaryObject(mainSeededComponent, tc, {
            appSettings: settingsB
        })
        verify(mainB !== null)
        wait(150)

        // Assertion 2 — Good IS: outer guard short-circuits even when
        // seed is real.
        compare(settingsB.previewRTMPUrl, "rtmp://203.0.113.7/userconfig/",
                "Variant B: user config must survive (non-empty seed)")
        // Assertion 3b — Bad NOT: no overwrite signal even for real seed.
        compare(spyB.count, 0,
                "Variant B: previewRTMPUrlChanged spy must remain 0")
    }
}
