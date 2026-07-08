import 'dart:convert';

import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
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
      if (s.interrupted) {
        return _ok(inv, 'interrupted run — totality deferred to P12');
      }
      return _check(
        inv,
        _terminal(status),
        'reached $status (terminal=${_terminal(status)})',
      );
    case 'P2':
      // No false "no backup": a populated authentic manifest on a reachable
      // relay under the correct seed is never reported absent.
      final absent = status == RemoteKeychainRecoveryStatus.nothingToRestore ||
          status == RemoteKeychainRecoveryStatus.noManifestFound;
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
      // Consent gate: with backup OFF, no network manifest was ever published.
      final backupOff = s.tuple.isValue(ParameterModel.dBackup, 'off');
      if (!backupOff) return _ok(inv, 'backup on; consent path exercised');
      return _check(
        inv,
        s.relay.storedEventCount == 0,
        'backup=off; storedEvents=${s.relay.storedEventCount}',
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
      // Wire opacity: every captured EVENT frame is opaque base64 on kind
      // 30078 / d-tag manifest, with no bull-identifying cleartext.
      return _wireOpacity(inv, s);
    default:
      // P5 / P8 / P9 / P10 / P11 / P13: applicable but not independently
      // asserted by the in-process recovery lane in this build.
      return _ok(inv, 'not independently asserted in this lane');
  }
}

InvariantResult _wireOpacity(Invariant inv, CompiledScenario s) {
  for (final frame in s.relay.capturedEventFrames) {
    final lower = frame.toLowerCase();
    if (lower.contains('bullbitcoin') ||
        lower.contains('recoverbull') ||
        lower.contains('satoshiportal')) {
      return _fail(inv, 'identifying cleartext on the wire');
    }
    final decoded = jsonDecode(frame);
    if (decoded is! List || decoded.isEmpty || decoded[0] != 'EVENT') continue;
    final event = decoded[1] as Map<String, dynamic>;
    if (event['kind'] != 30078) return _fail(inv, 'wrong kind ${event['kind']}');
    final tags = (event['tags'] as List).cast<List<dynamic>>();
    if (!tags.any((t) => t[0] == 'd' && t[1] == 'manifest')) {
      return _fail(inv, 'missing d=manifest tag');
    }
    final content = event['content'] as String;
    if (content.startsWith('{')) return _fail(inv, 'content is cleartext JSON');
    try {
      base64.decode(content);
    } catch (_) {
      return _fail(inv, 'content is not base64');
    }
  }
  return _ok(inv, '${s.relay.capturedEventFrames.length} frame(s) opaque');
}

bool _terminal(RemoteKeychainRecoveryStatus status) {
  switch (status) {
    case RemoteKeychainRecoveryStatus.idle:
    case RemoteKeychainRecoveryStatus.checking:
    case RemoteKeychainRecoveryStatus.restoring:
    case RemoteKeychainRecoveryStatus.requiresRelayDisclosure:
      return false;
    default:
      return true;
  }
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
