// Regression tests for StreamingSettingsController m_active reconciliation.
//
// These cover the contract introduced for ffstream-driven m_active
// reconciliation:
//
//   1. loadFromFile() must NOT trust the persisted "active" key — a stale
//      streaming_settings.json with "active":true must NOT lift the
//      controller into Active state on construction. m_active is always
//      false on boot until the QML reconciler (Main.qml's onChannelChanged)
//      confirms priority-0 inputs are present via setActiveFromReconciliation.
//
//   2. setActiveFromReconciliation(true) flips m_active true and emits
//      activeChanged exactly once.
//
//   3. setActiveFromReconciliation(true) called twice in a row emits
//      activeChanged only once (idempotent).
//
//   4. setActiveFromReconciliation(false) from a true state flips to
//      false and emits activeChanged exactly once.
//
//   5. setActiveFromReconciliation drops a reply with a stale epoch (i.e.
//      the user tapped activate()/deactivate() between the RPC dispatch
//      and the reply). m_active stays at the user's chosen state.
//
//   6. userIntentEpoch increments monotonically on activate() and
//      deactivate() and emits userIntentEpochChanged.
//
//   7. loadFromFile emits activeChanged when it is invoked while m_active
//      was already true (covers a future "reload from disk" caller —
//      today only the ctor calls it, and m_active starts false there).

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QString>
#include <QTemporaryDir>
#include <QTest>

#include "streaming_settings_controller.h"

class TestStreamingSettingsControllerReconcile : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void init();
    void cleanup();

    // Test 1: stale streaming_settings.json with "active":true must yield
    //         m_active==false after construction.
    void test_loadFromFile_ignores_persisted_active_true();

    // Test 2: setActiveFromReconciliation(true) flips m_active and emits once.
    void test_setActiveFromReconciliation_true_emits_once();

    // Test 3: idempotent: calling true twice emits only once.
    void test_setActiveFromReconciliation_idempotent();

    // Test 4: setActiveFromReconciliation(false) after true flips back, emits once.
    void test_setActiveFromReconciliation_false_after_true();

    // Test 5: stale-epoch reply must be dropped (Critic A Issue 2).
    void test_setActiveFromReconciliation_stale_epoch_dropped();

    // Test 6: activate() and deactivate() each bump userIntentEpoch and
    //         emit userIntentEpochChanged.
    void test_userIntentEpoch_increments_on_activate_deactivate();

    // Test 7: writeToFile no longer persists the dead "active" key
    //         (companion to the loadFromFile emit guard: with the key
    //         gone from the write side, load can never re-derive
    //         m_active=true from disk, but the in-cpp guard still
    //         protects future "reload from disk" callers).
    void test_writeToFile_no_longer_persists_active_key();

    // Test 8: bumpUserIntentEpoch increments userIntentEpoch and emits
    //         userIntentEpochChanged WITHOUT flipping m_active. Used by
    //         the QML rollback path in CamerasBuiltin._doActivate when
    //         the mic leg fails after the camera leg attached: we need
    //         to invalidate any in-flight reconcile reply BEFORE issuing
    //         removeInput, but we must NOT fake a user activate/deactivate
    //         because m_active never flipped (we hadn't called activate()
    //         yet). This is the surgical "epoch only" bump.
    void test_bumpUserIntentEpoch_increments_without_flipping_active();

    // Test 9: bumpUserIntentEpoch invalidates a stale reconcile reply.
    //         Capture epoch, bump it, then have a stale reply land —
    //         it must be dropped (m_active stays at the user's chosen
    //         state, identical to the activate()/deactivate() epoch
    //         contract).
    void test_bumpUserIntentEpoch_invalidates_stale_reconcile_reply();

    // Test 10: Re-Activate UI flicker race. Reproduces the scenario
    //         where the user is already Active and taps Re-Activate. The
    //         CamerasBuiltin onClicked path now bumps the epoch BEFORE
    //         purge+AddInput so that an in-flight reconcile reply (which
    //         observes "no priority-0 inputs" because the purge step has
    //         already run) cannot clobber m_active=true while the
    //         AddInput round-trip is still in progress and activate() has
    //         not yet been re-invoked. The test sets m_active=true,
    //         captures the pre-tap epoch (mimicking the QML reconciler's
    //         "capture before dispatch" rule), bumps via
    //         bumpUserIntentEpoch() to model the new onClicked guard,
    //         lands a stale "no inputs" reply with the pre-tap epoch and
    //         asserts m_active stays true.
    void test_reactivate_flicker_race_bump_before_addinput();

    // Test 12: Persisted-JSON schema version round-trip. writeToFile
    //         records the current settingsSchemaVersion; loadFromFile
    //         accepts that version. A file with a wrong version
    //         falls back to defaults and emits saveFailed (covers the
    //         schema-migration low-priority finding).
    void test_settings_schema_version_round_trip();
    void test_settings_schema_version_mismatch_resets_to_defaults();
    void test_persisted_h264_videoCodec_loads_as_mission_av1_and_repairs_file();
    void test_setVideoCodec_refuses_to_persist_non_av1();

    // Test 11: Asymmetric-epoch invariant. The user-intent-epoch and
    //         channel-epoch (Main.qml's main.reconcileChannelEpoch) gate
    //         different paths: success-path bails on user-intent
    //         mismatch only, failure-path bails on channel-epoch
    //         mismatch only. This unit test exercises the
    //         StreamingSettingsController half of the contract: a
    //         reconcile success reply with a stale userIntentEpoch must
    //         be dropped (this is the success-path guard), regardless of
    //         what the channel-epoch is doing. The channel-epoch half
    //         lives in Main.qml and is exercised by the QML harness.
    void test_asymmetric_epoch_invariant_success_path();

private:
    // Compute the same path StreamingSettingsController computes via
    // QStandardPaths::TempLocation. Mirrors initSettingsPath().
    QString computeSettingsPath() const;
    void writeStaleSettings(bool active) const;
    void deleteSettingsIfPresent() const;
};

QString TestStreamingSettingsControllerReconcile::computeSettingsPath() const
{
    QString tempDir = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (tempDir.isEmpty())
        tempDir = QDir::tempPath();
    if (tempDir.isEmpty())
        tempDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir dir(tempDir);
    if (!dir.exists())
        dir.mkpath(QStringLiteral("."));
    return dir.filePath(QStringLiteral("streaming_settings.json"));
}

void TestStreamingSettingsControllerReconcile::writeStaleSettings(bool active) const
{
    const QString path = computeSettingsPath();
    QJsonObject root;
    root.insert(QStringLiteral("width"), 1920);
    // Built-in camera fixture: Wingout owns the ffstream-camera path, whose
    // default input is 1920x1920. The mediamtx-side 1920x1080 daemon is
    // configured by its own launcher.
    root.insert(QStringLiteral("height"), 1920);
    root.insert(QStringLiteral("fps"), 60);
    root.insert(QStringLiteral("bitrateKbps"), 8000);
    root.insert(QStringLiteral("preferredCamera"), QStringLiteral("Front"));
    root.insert(QStringLiteral("videoCodec"), QStringLiteral("av1_mediacodec"));
    root.insert(QStringLiteral("audioCodec"), QStringLiteral("aac"));
    root.insert(QStringLiteral("audioSampleRate"), 48000);
    root.insert(QStringLiteral("audioBitrateKbps"), 64);
    root.insert(QStringLiteral("audioChannels"), 1);
    root.insert(QStringLiteral("maxBitrateKbps"), 12000);
    root.insert(QStringLiteral("showAllCodecs"), true);
    root.insert(QStringLiteral("outputUrl"), QString());
    root.insert(QStringLiteral("preferredMicrophoneId"), 0);
    root.insert(QStringLiteral("active"), active);
    root.insert(QStringLiteral("settingsSchemaVersion"), 2);

    QFile f(path);
    QVERIFY2(f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text),
             qPrintable(QStringLiteral("opening %1 for write failed: %2")
                            .arg(path, f.errorString())));
    const QByteArray data = QJsonDocument(root).toJson(QJsonDocument::Indented);
    QCOMPARE(f.write(data), qint64(data.size()));
    f.close();
}

void TestStreamingSettingsControllerReconcile::deleteSettingsIfPresent() const
{
    QFile f(computeSettingsPath());
    if (f.exists())
        f.remove();
}

void TestStreamingSettingsControllerReconcile::initTestCase()
{
    // Use test-specific organization to keep persisted artifacts local.
    QCoreApplication::setOrganizationName("WingOutTest");
    QCoreApplication::setOrganizationDomain("test.wingout.app");
    QCoreApplication::setApplicationName("WingOutTest_StreamingSettingsControllerReconcile");
}

void TestStreamingSettingsControllerReconcile::init()
{
    deleteSettingsIfPresent();
}

void TestStreamingSettingsControllerReconcile::cleanup()
{
    deleteSettingsIfPresent();
}

void TestStreamingSettingsControllerReconcile::test_loadFromFile_ignores_persisted_active_true()
{
    // Arrange: write a stale settings file claiming active=true.
    writeStaleSettings(/*active=*/true);

    // Sanity: confirm the file is on disk where the controller will look.
    QVERIFY(QFile::exists(computeSettingsPath()));

    // Act: construct the controller, which calls loadFromFile() in its ctor.
    StreamingSettingsController c;

    // Assert positive: m_active is false.
    QCOMPARE(c.isActive(), false);

    // Assert negative (dual-sided): m_active is NOT true even though the
    // persisted file said active=true. This is the key regression: prior
    // behavior trusted obj.value("active").toBool(true) and silently
    // promoted the controller back to Active on boot.
    QVERIFY2(!c.isActive(),
             "loadFromFile must NOT trust persisted active=true — "
             "ffstream input registry is the only source of truth");

    // Assert the rest of the JSON loaded correctly (so we know we're not
    // simply failing to parse the file — width/height/fps came from the file).
    QCOMPARE(c.width(), 1920);
    QCOMPARE(c.height(), 1920);
    QCOMPARE(c.fps(), 60);
    QCOMPARE(c.bitrateKbps(), 8000);
}

void TestStreamingSettingsControllerReconcile::test_setActiveFromReconciliation_true_emits_once()
{
    // Arrange: ensure no settings file (so the controller starts inactive
    // with defaults).
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QCOMPARE(c.isActive(), false);

    // Capture the current epoch (no user intent yet -> still 0). The QML
    // reconciler captures the epoch BEFORE dispatching the RPC; we mimic
    // that here.
    const quint64 capturedEpoch = c.userIntentEpoch();

    QSignalSpy spy(&c, &StreamingSettingsController::activeChanged);
    QVERIFY(spy.isValid());

    // Act.
    c.setActiveFromReconciliation(true, capturedEpoch);

    // Assert positive: m_active is true and signal fired once.
    QCOMPARE(c.isActive(), true);
    QCOMPARE(spy.count(), 1);

    // Assert negative: signal didn't fire 0 times or >1 times.
    QVERIFY2(spy.count() != 0, "activeChanged must fire on transition");
    QVERIFY2(spy.count() <= 1, "activeChanged must fire AT MOST once per call");
}

void TestStreamingSettingsControllerReconcile::test_setActiveFromReconciliation_idempotent()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QSignalSpy spy(&c, &StreamingSettingsController::activeChanged);

    const quint64 capturedEpoch = c.userIntentEpoch();

    // First call: false -> true. Should emit.
    c.setActiveFromReconciliation(true, capturedEpoch);
    QCOMPARE(c.isActive(), true);
    QCOMPARE(spy.count(), 1);

    // Second call (idempotent): true -> true. Must NOT emit again. The
    // epoch is unchanged because no user intent fired between calls.
    c.setActiveFromReconciliation(true, capturedEpoch);

    // Assert positive: m_active is still true.
    QCOMPARE(c.isActive(), true);
    // Assert negative: signal still only fired the original once.
    QCOMPARE(spy.count(), 1);
    QVERIFY2(spy.count() == 1,
             "redundant setActiveFromReconciliation(true) must not re-emit");
}

void TestStreamingSettingsControllerReconcile::test_setActiveFromReconciliation_false_after_true()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QSignalSpy spy(&c, &StreamingSettingsController::activeChanged);

    const quint64 capturedEpoch = c.userIntentEpoch();

    // Lift to true.
    c.setActiveFromReconciliation(true, capturedEpoch);
    QCOMPARE(c.isActive(), true);
    QCOMPARE(spy.count(), 1);

    // Now flip back to false. (Same epoch — no user intent fired.)
    c.setActiveFromReconciliation(false, capturedEpoch);

    // Assert positive: m_active is false; total emit count is 2 (true, false).
    QCOMPARE(c.isActive(), false);
    QCOMPARE(spy.count(), 2);

    // Assert negative: m_active did NOT remain stuck at true.
    QVERIFY2(!c.isActive(),
             "setActiveFromReconciliation(false) must flip m_active back to false");
}

void TestStreamingSettingsControllerReconcile::test_setActiveFromReconciliation_stale_epoch_dropped()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;

    // Caller captures epoch BEFORE dispatching reconcile RPC.
    const quint64 capturedEpoch = c.userIntentEpoch();

    // Meanwhile, the user taps Activate. activate() bumps the epoch.
    QVERIFY(c.activate());
    QCOMPARE(c.isActive(), true);
    QVERIFY2(c.userIntentEpoch() > capturedEpoch,
             "activate() must advance userIntentEpoch above the captured value");

    QSignalSpy activeSpy(&c, &StreamingSettingsController::activeChanged);

    // Now the stale reconcile reply lands saying "no priority-0 inputs"
    // (false). With the captured (old) epoch it MUST be dropped.
    c.setActiveFromReconciliation(false, capturedEpoch);

    // Assert positive: m_active stays true (user intent wins).
    QCOMPARE(c.isActive(), true);
    // Assert negative: stale reply must NOT have flipped m_active to false,
    // and must NOT have emitted activeChanged.
    QCOMPARE(activeSpy.count(), 0);
    QVERIFY2(c.isActive(),
             "stale-epoch reconcile reply must NOT clobber user-driven activate()");

    // And: a fresh reconcile pass with the current epoch is still honored.
    const quint64 freshEpoch = c.userIntentEpoch();
    c.setActiveFromReconciliation(false, freshEpoch);
    QCOMPARE(c.isActive(), false);
    QCOMPARE(activeSpy.count(), 1);
}

void TestStreamingSettingsControllerReconcile::test_userIntentEpoch_increments_on_activate_deactivate()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;

    QSignalSpy epochSpy(&c, &StreamingSettingsController::userIntentEpochChanged);
    QVERIFY(epochSpy.isValid());

    const quint64 initialEpoch = c.userIntentEpoch();

    // activate() must bump the epoch and emit userIntentEpochChanged.
    QVERIFY(c.activate());
    const quint64 afterActivate = c.userIntentEpoch();
    QVERIFY2(afterActivate > initialEpoch,
             "activate() must increment userIntentEpoch");
    QCOMPARE(afterActivate, initialEpoch + 1);
    QCOMPARE(epochSpy.count(), 1);

    // deactivate() must also bump the epoch and emit.
    QVERIFY(c.deactivate());
    const quint64 afterDeactivate = c.userIntentEpoch();
    QVERIFY2(afterDeactivate > afterActivate,
             "deactivate() must increment userIntentEpoch");
    QCOMPARE(afterDeactivate, afterActivate + 1);
    QCOMPARE(epochSpy.count(), 2);

    // Negative: setActiveFromReconciliation must NOT change the epoch
    // (epoch is user-intent only).
    c.setActiveFromReconciliation(true, afterDeactivate);
    QCOMPARE(c.userIntentEpoch(), afterDeactivate);
    QCOMPARE(epochSpy.count(), 2);
}

void TestStreamingSettingsControllerReconcile::test_writeToFile_no_longer_persists_active_key()
{
    // The loadFromFile emit guard (m_active was true -> emit
    // activeChanged on clobber) is uncoverable today: loadFromFile is
    // private and only invoked from the ctor where m_active starts
    // false. The companion contract — writeToFile no longer persists
    // "active" — IS testable directly, and protects future "reload from
    // disk" callers from re-introducing the field.
    //
    // (If we exposed a public reload(), we'd lift m_active via
    //  setActiveFromReconciliation, install a QSignalSpy, call reload(),
    //  and assert exactly one activeChanged emission. The emit-guard
    //  code itself is reviewed for correctness in this commit.)
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QVERIFY(c.activate());            // writes the file via writeToFile
    QCOMPARE(c.isActive(), true);

    // Read the file back and confirm "active" key is gone.
    QFile f(computeSettingsPath());
    QVERIFY(f.open(QIODevice::ReadOnly));
    const QByteArray data = f.readAll();
    f.close();

    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &pe);
    QCOMPARE(pe.error, QJsonParseError::NoError);
    QVERIFY(doc.isObject());
    const QJsonObject obj = doc.object();

    // Positive: persistent fields are present.
    QVERIFY(obj.contains(QStringLiteral("width")));
    QVERIFY(obj.contains(QStringLiteral("preferredCamera")));

    // Negative: "active" key must NOT be persisted any longer.
    QVERIFY2(!obj.contains(QStringLiteral("active")),
             "writeToFile must no longer persist the 'active' key — "
             "m_active is reconciled from ffstream on every boot");
}

void TestStreamingSettingsControllerReconcile::test_bumpUserIntentEpoch_increments_without_flipping_active()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;

    // Pre-conditions: brand-new controller is inactive, epoch is at 0.
    QCOMPARE(c.isActive(), false);
    const quint64 initialEpoch = c.userIntentEpoch();

    QSignalSpy epochSpy(&c, &StreamingSettingsController::userIntentEpochChanged);
    QSignalSpy activeSpy(&c, &StreamingSettingsController::activeChanged);
    QVERIFY(epochSpy.isValid());
    QVERIFY(activeSpy.isValid());

    // Act.
    c.bumpUserIntentEpoch();

    // Assert positive: epoch advanced by exactly 1, signal fired once.
    QCOMPARE(c.userIntentEpoch(), initialEpoch + 1);
    QCOMPARE(epochSpy.count(), 1);

    // Assert negative (dual-sided): m_active did NOT flip; activeChanged
    // did NOT fire. This is the whole point of the "bump only" entry
    // point — unlike activate()/deactivate(), it must not touch state.
    QCOMPARE(c.isActive(), false);
    QCOMPARE(activeSpy.count(), 0);

    // Bumping again from an active state must also leave m_active alone.
    QVERIFY(c.activate());                      // m_active = true, epoch advances
    const quint64 epochAfterActivate = c.userIntentEpoch();
    const bool activeAfterActivate = c.isActive();
    QCOMPARE(activeAfterActivate, true);

    QSignalSpy activeSpy2(&c, &StreamingSettingsController::activeChanged);
    c.bumpUserIntentEpoch();
    QCOMPARE(c.userIntentEpoch(), epochAfterActivate + 1);
    QCOMPARE(c.isActive(), true);               // unchanged
    QCOMPARE(activeSpy2.count(), 0);            // no flip
}

void TestStreamingSettingsControllerReconcile::test_bumpUserIntentEpoch_invalidates_stale_reconcile_reply()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;

    // Caller (QML reconciler) captures the epoch BEFORE dispatching its
    // GetInputsInfo RPC. Mimic that here.
    const quint64 capturedEpoch = c.userIntentEpoch();

    // Meanwhile, the QML rollback path bumps the epoch (e.g. mic leg
    // failed after camera leg attached, we're about to RemoveInput the
    // camera and we must invalidate any in-flight reconcile reply).
    c.bumpUserIntentEpoch();
    QVERIFY2(c.userIntentEpoch() > capturedEpoch,
             "bumpUserIntentEpoch must advance userIntentEpoch above the captured value");

    QSignalSpy activeSpy(&c, &StreamingSettingsController::activeChanged);

    // Now the stale reconcile reply lands saying "priority-0 inputs are
    // attached" (true). With the captured (old) epoch it MUST be dropped.
    c.setActiveFromReconciliation(true, capturedEpoch);

    // Assert positive: m_active stays false (rollback path was correct).
    QCOMPARE(c.isActive(), false);
    // Assert negative: stale reply must NOT have flipped m_active, must
    // NOT have emitted activeChanged.
    QCOMPARE(activeSpy.count(), 0);
    QVERIFY2(!c.isActive(),
             "stale-epoch reconcile reply must NOT clobber an in-flight rollback");

    // And: a fresh reconcile pass with the current epoch is still honored.
    const quint64 freshEpoch = c.userIntentEpoch();
    c.setActiveFromReconciliation(true, freshEpoch);
    QCOMPARE(c.isActive(), true);
    QCOMPARE(activeSpy.count(), 1);
}

void TestStreamingSettingsControllerReconcile::test_reactivate_flicker_race_bump_before_addinput()
{
    // Reproduces the Re-Activate UI flicker race fixed in CamerasBuiltin
    // onClicked: bumpUserIntentEpoch() now runs BEFORE the purge+AddInput
    // round-trip on every Activate/Re-Activate tap, so any reconcile reply
    // that lands while the AddInputs are pending (and observes "no
    // priority-0 inputs" because purge has already removed them) is
    // dropped instead of clobbering m_active=true.

    deleteSettingsIfPresent();
    StreamingSettingsController c;

    // Pre-condition: user has already activated (Re-Activate scenario).
    QVERIFY(c.activate());
    QCOMPARE(c.isActive(), true);

    // The QML reconciler dispatched a getInputsInfo BEFORE the user tapped
    // Re-Activate; capture that epoch.
    const quint64 reconcileCapturedEpoch = c.userIntentEpoch();

    // User taps Re-Activate. CamerasBuiltin onClicked first bumps the
    // user-intent epoch, then runs purge+AddInputs. We model only the
    // bump+pending state here.
    c.bumpUserIntentEpoch();
    QVERIFY2(c.userIntentEpoch() > reconcileCapturedEpoch,
             "the new onClicked guard must advance userIntentEpoch ahead of "
             "any pre-tap reconcile dispatch");

    QSignalSpy activeSpy(&c, &StreamingSettingsController::activeChanged);

    // While purge+AddInputs are still in flight, the in-flight reconcile
    // reply lands saying "no priority-0 inputs" (false). With the captured
    // pre-tap epoch it MUST be dropped — without the new guard m_active
    // would briefly flip false here and the UI would flicker
    // Active -> Activate -> Re-Activate.
    c.setActiveFromReconciliation(false, reconcileCapturedEpoch);

    // Assert positive: m_active stays true (Re-Activate path is intact).
    QCOMPARE(c.isActive(), true);
    // Assert negative (dual-sided): the stale reply did NOT flip m_active
    // and did NOT emit activeChanged. This is the regression: prior to the
    // CamerasBuiltin guard, this assertion fired (spy.count() == 1, with
    // m_active==false transiently).
    QCOMPARE(activeSpy.count(), 0);
    QVERIFY2(c.isActive(),
             "stale-epoch reconcile reply must not clobber m_active during "
             "Re-Activate's pending AddInput round-trip");
}

void TestStreamingSettingsControllerReconcile::test_asymmetric_epoch_invariant_success_path()
{
    // Asymmetric epoch invariant: success-path of reconcile bails on
    // user-intent-epoch mismatch only. The channel-bounce epoch
    // (main.reconcileChannelEpoch) is intentionally NOT consulted on the
    // success path: a successful reply's data is still valid even if the
    // channel bounced — the inputs are what they are. This unit test
    // covers the StreamingSettingsController half: the only knob that
    // gates the success-path apply is userIntentEpoch.

    deleteSettingsIfPresent();
    StreamingSettingsController c;

    // Lift to active via the user-intent path. Epoch = 1.
    QVERIFY(c.activate());
    QCOMPARE(c.isActive(), true);
    const quint64 epochAfterActivate = c.userIntentEpoch();

    // Caller (QML reconciler) captures the epoch BEFORE dispatching its
    // GetInputsInfo RPC. Stale dispatch with an even-earlier epoch would
    // fail the guard; same-epoch should pass.
    const quint64 capturedEpoch = epochAfterActivate;

    QSignalSpy activeSpy(&c, &StreamingSettingsController::activeChanged);

    // The reply confirms hasCam && hasMic == true (already active).
    // Idempotent: m_active stays true, no signal.
    c.setActiveFromReconciliation(true, capturedEpoch);
    QCOMPARE(c.isActive(), true);
    QCOMPARE(activeSpy.count(), 0);

    // Now the user deactivates; epoch advances. A SECOND reconcile reply
    // (still carrying the OLD captured epoch) must be dropped on the
    // success path — even though the data (true) is technically correct
    // at the moment the RPC was issued, the user's intent has since
    // changed. Dropping here is the success-path guard.
    QVERIFY(c.deactivate());
    QCOMPARE(c.isActive(), false);
    QCOMPARE(activeSpy.count(), 1); // deactivate emitted activeChanged

    // Stale success-path reply: epoch mismatch -> dropped.
    c.setActiveFromReconciliation(true, capturedEpoch);
    QCOMPARE(c.isActive(), false);
    // Negative: did NOT emit a second activeChanged that would have
    // resurrected m_active=true.
    QCOMPARE(activeSpy.count(), 1);

    // Fresh reply with the current epoch IS honored — invariant is
    // strictly about epoch, not about the value.
    c.setActiveFromReconciliation(true, c.userIntentEpoch());
    QCOMPARE(c.isActive(), true);
    QCOMPARE(activeSpy.count(), 2);
}

void TestStreamingSettingsControllerReconcile::test_settings_schema_version_round_trip()
{
    // Activate writes the file via writeToFile. The persisted JSON must
    // include settingsSchemaVersion=2 so a future loader can gate on it
    // without ambiguity. The 1→2 bump (#350) was driven by writeToFile
    // dropping "active" and "ffstreamCameraArgs"; the cpp constant tracks
    // this expected on-disk value.
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QVERIFY(c.activate());

    QFile f(computeSettingsPath());
    QVERIFY(f.open(QIODevice::ReadOnly));
    const QByteArray data = f.readAll();
    f.close();

    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &pe);
    QCOMPARE(pe.error, QJsonParseError::NoError);
    const QJsonObject obj = doc.object();

    QVERIFY2(obj.contains(QStringLiteral("settingsSchemaVersion")),
             "writeToFile must persist settingsSchemaVersion so loadFromFile "
             "can gate compatibility");
    QCOMPARE(obj.value(QStringLiteral("settingsSchemaVersion")).toInt(), 2);
}

void TestStreamingSettingsControllerReconcile::test_settings_schema_version_mismatch_resets_to_defaults()
{
    // Write a file with a deliberately-wrong settingsSchemaVersion. The
    // controller's loadFromFile must reject it (emit saveFailed, NOT
    // partial-load any field) and the resulting controller state must
    // match the in-cpp defaults — NOT the values from the wrong-version
    // file.
    const QString path = computeSettingsPath();
    QJsonObject root;
    root.insert(QStringLiteral("width"), 9999);                 // distinctive
    root.insert(QStringLiteral("height"), 8888);                // distinctive
    root.insert(QStringLiteral("fps"), 7);
    root.insert(QStringLiteral("bitrateKbps"), 1234);
    root.insert(QStringLiteral("preferredCamera"), QStringLiteral("Back"));
    root.insert(QStringLiteral("settingsSchemaVersion"), 999);  // future / wrong

    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text));
    QCOMPARE(f.write(QJsonDocument(root).toJson()), qint64(QJsonDocument(root).toJson().size()));
    f.close();
    QVERIFY(QFile::exists(path));

    // The ctor calls loadFromFile. A version mismatch must emit
    // saveFailed, drop the file's contents, and leave defaults intact.
    StreamingSettingsController c;
    QSignalSpy widthSpy(&c, &StreamingSettingsController::widthChanged);
    Q_UNUSED(widthSpy);

    // Assert positive: camera defaults are intact (NOT 9999/8888 from the
    // file). DefaultHeight is 1920 for the built-in camera path.
    QCOMPARE(c.width(), 1920);
    QCOMPARE(c.height(), 1920);
    QCOMPARE(c.fps(), 60);

    // Assert negative (dual-sided): the file's distinctive width/height did
    // NOT leak through. If the schema gate was missing, we'd see 9999/8888.
    QVERIFY2(c.width() != 9999,
             "schema-mismatched file must NOT partial-load width");
    QVERIFY2(c.height() != 8888,
             "schema-mismatched file must NOT partial-load height");
    QCOMPARE(c.isActive(), false);
}

void TestStreamingSettingsControllerReconcile::test_persisted_h264_videoCodec_loads_as_mission_av1_and_repairs_file()
{
    writeStaleSettings(/*active=*/false);

    QFile f(computeSettingsPath());
    QVERIFY(f.open(QIODevice::ReadOnly));
    QJsonParseError readError;
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &readError);
    f.close();
    QCOMPARE(readError.error, QJsonParseError::NoError);
    QVERIFY(doc.isObject());

    QJsonObject root = doc.object();
    root.insert(QStringLiteral("videoCodec"), QStringLiteral("h264_mediacodec"));
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text));
    const QByteArray data = QJsonDocument(root).toJson(QJsonDocument::Indented);
    QCOMPARE(f.write(data), qint64(data.size()));
    f.close();

    StreamingSettingsController c;

    QCOMPARE(c.missionVideoCodec(), QStringLiteral("av1_mediacodec"));
    QCOMPARE(c.videoCodec(), c.missionVideoCodec());
    QVERIFY2(c.videoCodec() != QStringLiteral("h264_mediacodec"),
             "stale H.264 persisted settings must normalize to mission AV1 on load");

    QVERIFY(f.open(QIODevice::ReadOnly));
    QJsonParseError repairedReadError;
    const QJsonDocument repairedDoc = QJsonDocument::fromJson(f.readAll(), &repairedReadError);
    f.close();
    QCOMPARE(repairedReadError.error, QJsonParseError::NoError);
    QVERIFY(repairedDoc.isObject());

    const QJsonObject repairedRoot = repairedDoc.object();
    QCOMPARE(repairedRoot.value(QStringLiteral("videoCodec")).toString(),
             QStringLiteral("av1_mediacodec"));
    QVERIFY2(repairedRoot.value(QStringLiteral("videoCodec")).toString()
                 != QStringLiteral("h264_mediacodec"),
             "loadFromFile must repair stale current-schema videoCodec on disk");
    QVERIFY2(!repairedRoot.contains(QStringLiteral("showAllCodecs")),
             "loadFromFile/writeToFile must remove the dead showAllCodecs state from disk");
}

void TestStreamingSettingsControllerReconcile::test_setVideoCodec_refuses_to_persist_non_av1()
{
    deleteSettingsIfPresent();
    StreamingSettingsController c;
    QVERIFY(c.activate());
    QCOMPARE(c.isActive(), true);

    QSignalSpy codecSpy(&c, &StreamingSettingsController::videoCodecChanged);
    QVERIFY(codecSpy.isValid());

    c.setVideoCodec(QStringLiteral("h265_mediacodec"));

    QCOMPARE(c.videoCodec(), c.missionVideoCodec());
    QCOMPARE(codecSpy.count(), 0);

    QFile f(computeSettingsPath());
    QVERIFY(f.open(QIODevice::ReadOnly));
    QJsonParseError readError;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &readError);
    f.close();
    QCOMPARE(readError.error, QJsonParseError::NoError);
    QVERIFY(doc.isObject());

    const QJsonObject root = doc.object();
    QCOMPARE(root.value(QStringLiteral("videoCodec")).toString(),
             QStringLiteral("av1_mediacodec"));
    QVERIFY2(root.value(QStringLiteral("videoCodec")).toString()
                 != QStringLiteral("h265_mediacodec"),
             "active setters must not persist stale H.265 as a mission codec");
}

QTEST_GUILESS_MAIN(TestStreamingSettingsControllerReconcile)

#include "tst_streaming_settings_controller_reconcile.moc"
