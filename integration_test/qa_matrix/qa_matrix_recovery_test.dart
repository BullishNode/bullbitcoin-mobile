import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import 'support/matrix_runner.dart';
import 'support/named_case.dart';

// Phase-1 crown-jewel catalog (GETPAID-APP-E2E-FAILURE-MATRIX §4): the named
// recovery permutations, each a hand-authored tuple driven through the SAME
// engine machinery (oracle + feasibility + invariants) as the generated sweep.
// Every case drives the app's real RemoteKeychainRecoveryCubit at cubit level.
//
// Single-relay S-INJECT lane; the two-relay cells (older-populated / divergent)
// and the crafted newer-version fixture are Phase-1 remainder and assert as a
// non-fatal Blocked here, so the report stays honest about what is proven.
//
// Fork-only overlay; run directly:
//   fvm flutter test integration_test/qa_matrix/qa_matrix_recovery_test.dart
Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  final records = <EvidenceRecord>[];

  Future<EvidenceRecord> run(GeneratedCase c) async {
    final record = await runCase(locator, c);
    records.add(record);
    return record;
  }

  Future<void> expectClass(
    GeneratedCase c,
    ExpectedRecoveryClass expected,
  ) async {
    final r = await run(c);
    expect(
      r.outcome,
      CaseOutcome.passed,
      reason: '${c.id} [${c.scenarioClass}] message=${r.message}',
    );
    expect(r.observedClass, expected, reason: '${c.id}');
  }

  Future<void> expectPassed(GeneratedCase c) async {
    final r = await run(c);
    expect(
      r.outcome,
      CaseOutcome.passed,
      reason: '${c.id} [${c.scenarioClass}] message=${r.message}',
    );
  }

  Future<void> expectBlocked(GeneratedCase c) async {
    final r = await run(c);
    expect(
      r.outcome,
      CaseOutcome.blocked,
      reason: '${c.id} should be a non-fatal Blocked in this lane',
    );
  }

  // 3. Happy path — a current authentic manifest restores byte-identically.
  test('FM-F5-HP: current manifest restores', () async {
    await expectClass(namedCase('hp-current', {}), ExpectedRecoveryClass.restored);
  });

  // 1. Wrong seed — the seed-derived coordinate is empty, never another's data.
  test('FM-F5-WS: wrong seed sees an empty coordinate', () async {
    await expectClass(
      namedCase('ws-wrong-seed', {
        ParameterModel.dSeed: 'wrong',
        ParameterModel.dManifest: 'none',
      }),
      ExpectedRecoveryClass.nothingToRestore,
    );
  });

  // 2. No backup ever made — nothing published, never a fake "restored".
  test('FM-F5-RB: no backup published', () async {
    await expectClass(
      namedCase('rb-no-backup', {
        ParameterModel.dBackup: 'off',
        ParameterModel.dManifest: 'none',
      }),
      ExpectedRecoveryClass.nothingToRestore,
    );
  });

  // 10/tampered. A tampered event fails the authenticity boundary → treated as
  // absent, never materialised (P6).
  test('FM-F5-HA: tampered event is dropped, never restored', () async {
    await expectPassed(
      namedCase('ha-tampered', {ParameterModel.dManifest: 'tampered'}),
    );
  });

  // 10/forged. A forged-author event on the coordinate is dropped (P6).
  test('FM-F5-HA: forged-author event is dropped', () async {
    await expectPassed(
      namedCase('ha-forged', {ParameterModel.dManifest: 'forged-author'}),
    );
  });

  // 12. Relays fully unreachable → relaysUnavailable (loud), distinct from
  // "absent" (P2), and never a hang (P1).
  test('FM-F5-IB: all relays unreachable', () async {
    await expectClass(
      namedCase('ib-all-down', {ParameterModel.dRelay: 'all-down'}),
      ExpectedRecoveryClass.relaysUnavailable,
    );
  });

  // 12. Offline network → relaysUnavailable.
  test('FM-F5-IB: offline network', () async {
    await expectClass(
      namedCase('ib-offline', {ParameterModel.dNetwork: 'offline'}),
      ExpectedRecoveryClass.relaysUnavailable,
    );
  });

  // 12. Flood beyond the fetch limit still resolves the real manifest (RE).
  test('FM-F5-RE: relay flood is bounded, still restores', () async {
    await expectClass(
      namedCase('re-flood', {ParameterModel.dRelay: 'one-flood'}),
      ExpectedRecoveryClass.restored,
    );
  });

  // 11. A relay that rejects our REQ-OK but still serves stored events: the
  // fetch path only reads events, so a reachable relay with the manifest
  // restores (a publish-side neverOk does not lose a real backup).
  test('FM-F5-IB: one relay rejecting still restores', () async {
    await expectPassed(
      namedCase('ib-one-reject', {ParameterModel.dRelay: 'one-reject'}),
    );
  });

  // 6. Empty-only union (single relay) → nothingToRestore, never fake "restored"
  // (P4).
  test('FM-F5-PF: empty-newest single relay restores nothing', () async {
    await expectClass(
      namedCase('pf-empty', {ParameterModel.dManifest: 'empty-newest'}),
      ExpectedRecoveryClass.nothingToRestore,
    );
  });

  // 13. Interrupted mid-recovery — the guard discards the in-flight result; no
  // premature/corrupt restore (P12).
  test('FM-F5-IM: interrupted mid-recovery leaves no corrupt state', () async {
    await expectPassed(
      namedCase('im-mid-recovery', {
        ParameterModel.dInterrupt: 'mid-recovery',
      }),
    );
  });

  // 8. DG-3 heal path: a lapsed registration on a Lightning-Address wallet set.
  test('FM-F5-RB: lapsed registration during recovery', () async {
    await expectPassed(
      namedCase('rb-lapsed', {ParameterModel.dServer: 'up-lapsed'}),
    );
  });

  // 4/5/9. Two-relay + crafted-fixture cells are Phase-1 remainder (E9 harness).
  test('FM-F5-RB: older-populated is Blocked (E9 remainder)', () async {
    await expectBlocked(
      namedCase('rb-older', {ParameterModel.dManifest: 'older-populated'}),
    );
  });
  test('FM-F5-VS: newer-version is Blocked (crafted-fixture remainder)', () async {
    await expectBlocked(
      namedCase('vs-newer', {ParameterModel.dManifest: 'newer-version'}),
    );
  });
  test('FM-F5-PF: divergent is Blocked (E9 remainder)', () async {
    await expectBlocked(
      namedCase('pf-divergent', {ParameterModel.dRelay: 'divergent'}),
    );
  });

  tearDownAll(() {
    // ignore: avoid_print
    print(MatrixReport(records).render());
  });
}
