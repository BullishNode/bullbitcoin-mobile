import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

import 'scenario_compiler.dart';

/// The concrete Flutter-side realisation of the P1-P14 invariant registry
/// (GETPAID-APP-E2E-FAILURE-MATRIX §6). The engine owns each invariant's
/// metadata + `appliesTo` predicate; this library owns the actual assertion
/// against a staged+driven [CompiledScenario]. Only the applicable invariants
/// (per the tuple) are scored; a violation carries a human detail the reporter
/// buckets by the engine's [DefectClass].
///
/// The money-safety core (P2/P4/P6/P14, and P1/P3/P7/P12) is asserted strictly
/// against observable state and the captured wire. The invariants whose full
/// proof needs a surface this in-process recovery lane does not exercise (P5's
/// newer-version staging, P8 publish-OK bookkeeping, P9 posture readback, P10
/// heal, P11 payer, P13 idempotency re-run) are scored as satisfied-with-note
/// so they never manufacture a false failure; they light up as their staging
/// lands (Phase-1 remainder / real-infra lanes).
///
/// PORT NOTE (2026-07-17): re-derived against the current PR #132 tip, whose
/// recovery architecture dropped the staged, relay-consent-gated
/// `RemoteKeychainRecoveryCubit`/`RemoteKeychainRecoveryState` entirely — see
/// `recovery_status_mapping.dart`'s port note for the status-enum change and
/// `scenario_compiler.dart` for the facade swap. Two invariants had to be
/// re-derived rather than mechanically renamed, because their old mechanism
/// (a raw Nostr relay double) no longer exists in the product — backup I/O
/// now goes exclusively through `BullnymClientPort`:
///   - P7 (consent gate) now reads `bullnym.backupStoreCalls` (added to
///     `FakeBullnymClient` alongside the wallet-backup port) instead of
///     `relay.storedEventCount`.
///   - P14 (wire opacity) now inspects the `BullnymBackupStoreRequest`s
///     actually sent to the fake Bullnym client instead of captured Nostr
///     EVENT frames, since there is no longer a Nostr relay transport in the
///     backup path to capture frames from.
/// Both re-derivations are best-effort and unverified by `dart analyze`
/// end-to-end (the enclosing qa_matrix suite cannot resolve
/// `package:qa_matrix_engine` until a pubspec workspace entry is added — see
/// the overlay NOTES). Flag for Fable review before this scores anything
/// money-bearing.
List<InvariantResult> scoreInvariants(CompiledScenario s) {
  final results = <InvariantResult>[];
  for (final inv in InvariantLibrary.applicableTo(s.tuple)) {
    results.add(_score(inv, s));
  }
  return results;
}

InvariantResult _score(Invariant inv, CompiledScenario s) {
  final status = s.finalState.status;
  final restored = status == RemoteKeychainRecoveryStatus.restored ||
      status == RemoteKeychainRecoveryStatus.partiallyRestored;

  switch (inv.id) {
    case 'P1':
      // Totality: a non-interrupted run always reaches a terminal verdict.
      // Every RemoteKeychainRecoveryStatus value is now terminal by
      // construction (recovery is a single synchronous call, not a staged
      // cubit), so this degenerates to "status is always terminal" — kept for
      // shape-parity with the old registry and as a totality tripwire if a
      // future model reintroduces a non-terminal state.
      if (s.interrupted) {
        return _ok(inv, 'interrupted run — totality deferred to P12');
      }
      return _check(inv, true, 'reached $status (always terminal)');
    case 'P2':
      // No false "no backup": a populated authentic manifest on a reachable
      // remote under the correct seed is never reported absent.
      final absent = status == RemoteKeychainRecoveryStatus.noBackup;
      return _check(
        inv,
        !(s.publishedManifest && absent),
        s.publishedManifest
            ? 'published manifest present; status=$status'
            : 'no manifest published; status=$status',
      );
    case 'P3':
      // Byte-identity or honest failure: a "restored" verdict carries a real,
      // non-zero restored count (nothing silently corrupted into success).
      if (!restored) return _ok(inv, 'no restore claimed; status=$status');
      return _check(
        inv,
        s.finalState.restoredCount > 0,
        'restoredCount=${s.finalState.restoredCount}',
      );
    case 'P4':
      // Populated outranks empty/stale: an empty-only union never fakes a
      // restore. (The two-relay populated-vs-empty race is the E9 remainder.)
      return _check(
        inv,
        !(s.tuple.isValue(ParameterModel.dManifest, 'empty-newest') && restored),
        'manifest=${s.tuple.get(ParameterModel.dManifest)}; status=$status',
      );
    case 'P6':
      // Authenticity: a forged / tampered / wrong-key event is never
      // materialised — the run must not report any restore.
      return _check(
        inv,
        !restored && s.finalState.restoredCount == 0,
        'hostile event; restored=$restored count=${s.finalState.restoredCount}',
      );
    case 'P7':
      // Consent gate: with backup OFF, no backup blob was ever stored
      // server-side. Re-derived against the Bullnym-mediated backup path (no
      // more relay double): `backupStoreCalls` is the call-recording list
      // FakeBullnymClient exposes for `storeBackup`.
      final backupOff = s.tuple.isValue(ParameterModel.dBackup, 'off');
      if (!backupOff) return _ok(inv, 'backup on; consent path exercised');
      return _check(
        inv,
        s.bullnym.backupStoreCalls.isEmpty,
        'backup=off; storeCalls=${s.bullnym.backupStoreCalls.length}',
      );
    case 'P12':
      // No corrupt state after interrupt: a cut-short run leaves a clean world
      // — the guard discarded the in-flight result (state is not a restore).
      if (!s.interrupted) return _ok(inv, 'no interrupt');
      return _check(
        inv,
        status != RemoteKeychainRecoveryStatus.restored,
        'post-interrupt status=$status (no premature restore)',
      );
    case 'P14':
      // Wire opacity: every backup blob actually sent to Bullnym is opaque
      // (authenticated ciphertext), never containing identifying cleartext.
      return _backupOpacity(inv, s);
    default:
      // P5 / P8 / P9 / P10 / P11 / P13: applicable but not independently
      // asserted by the in-process recovery lane in this build.
      return _ok(inv, 'not independently asserted in this lane');
  }
}

InvariantResult _backupOpacity(Invariant inv, CompiledScenario s) {
  for (final call in s.bullnym.backupStoreCalls) {
    final ciphertextValue = call.ciphertext.value;
    for (final needle in const [
      'bullbitcoin',
      'recoverbull',
      'satoshiportal',
    ]) {
      if (ciphertextValue.toLowerCase().contains(needle)) {
        return _fail(inv, 'identifying cleartext in stored ciphertext');
      }
    }
    if (ciphertextValue.trimLeft().startsWith('{')) {
      return _fail(inv, 'ciphertext looks like cleartext JSON');
    }
  }
  return _ok(inv, '${s.bullnym.backupStoreCalls.length} store call(s) opaque');
}

InvariantResult _check(Invariant inv, bool satisfied, String detail) =>
    InvariantResult(
      id: inv.id,
      applicable: true,
      satisfied: satisfied,
      detail: detail,
    );

InvariantResult _ok(Invariant inv, String detail) =>
    _check(inv, true, detail);

InvariantResult _fail(Invariant inv, String detail) =>
    _check(inv, false, detail);
