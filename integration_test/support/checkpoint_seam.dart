/// WP-KILL observability seam (release-cert plan §6 WP-KILL + Appendix E).
///
/// This file is deliberately NOT wired into any funded lane spec yet — it is
/// the reusable primitive a future funded kill lane adopts for the ONE class
/// of Appendix-A commitment point the app does not already durably record on
/// its own: **C7/C8**, "autosweep broadcast" / "autosweep confirmed-or-
/// locally-acknowledged" — the split boundary "broadcast done, local ack
/// pending" the plan calls out as the hard one (AB-08).
///
/// CORE RULE THIS FILE MUST NEVER VIOLATE (owner correction #4): kill
/// orchestration lives OUTSIDE the app, and a test-side signal is TIMING
/// information ONLY. [checkpointLine] exists so an external coordinator
/// watching stdout knows *when* to SIGKILL the process group — it is never
/// read back in place of the app's actual persisted state. After a kill+
/// relaunch, the assertion must always come from re-reading the real
/// on-device wallet/swap state (SQLite, keyring, wallet balance/UTXO set),
/// never from this line or from any "which cid did we aim for" marker.
///
/// Most Appendix-A commitment points do NOT need this seam at all, because
/// something already durably records them independent of any test code:
///   - C1/C2/C5 — the server's own tables (nym reservation, checkout/invoice
///     row, swap-claim row): observable by querying Bullnym directly.
///   - C3 — the coordinator's OWN append-only journal
///     (`coordinator/lib/src/journal.dart`) already journals step intent
///     durably BEFORE the irreversible operation runs; that journal IS the
///     checkpoint, no seam needed.
///   - C4 (payer broadcast) — the guarded payer's own intent-before-send
///     journal is the durable record of "an attempt left the payer's
///     control"; the raw in-flight network/HTLC state itself is not
///     durably observable by anyone (not even the payer — the plan notes
///     "payer cannot prove settlement itself" for LN) and is covered by
///     deterministic AB-04 idempotency testing instead, not by a kill-point
///     seam here.
///   - C6/C9 — a destination/default-wallet credit is a wallet balance/UTXO
///     change; once observed it is already sitting in the app's own
///     persisted wallet store, readable after any relaunch.
///   - C10 — the coordinator's own journal terminal write; durable by
///     construction.
/// See the WP-KILL report (`getpaid-e2e-phaseA-KILL-2026-07-17.md`) for the
/// full commitment-point observability table and reasoning.
///
/// Only C7 and C8 lack an obviously distinct durable marker for the EXACT
/// instant "broadcast just returned, ack not yet processed" — the sweep
/// transaction's existence becomes visible in the wallet's own persisted
/// tx/UTXO cache once broadcast, which is enough to PROVE it happened, but
/// an external kill orchestrator watching only on-disk state from outside
/// cannot reliably land a kill in that narrow pre-ack window without a
/// synchronous signal. Hence: a minimal seam, for timing only.
library;

import 'dart:convert';

/// Builds one `CHECKPOINT {json}` line, matching the exact convention already
/// used by the funded lane specs (see `funded_btcpay100_fixtures.dart`
/// `btcpayCheckpointLine`, `get_paid_page102_funded_test.dart` `_checkpoint`,
/// etc.), plus an explicit `cid` — the Appendix-A commitment-point id
/// (`C1`..`C10`) — so an external kill watcher
/// (`getpaid-e2e-chunk6-page102/scripts/lib/checkpoint_kill.sh`) can match on
/// one stable field instead of parsing free-text `step` names.
///
/// [cid] must be one the checkpoint-observability table marks "needs-seam"
/// (currently only `C7`/`C8`) — this is a lightweight assertion, not a hard
/// gate, because the authoritative list lives in the WP-KILL report, not in
/// code; it exists to catch an accidental call for a boundary that should
/// already be natively observable and therefore should not grow a seam.
String checkpointLine(
  String step, {
  required String cid,
  String status = 'ok',
  Map<String, Object?> data = const {},
  String Function(String)? redactor,
}) {
  assert(
    const {'C7', 'C8'}.contains(cid),
    'checkpointLine is a WP-KILL timing-only seam for the boundaries the app '
    'does not already durably record (currently C7/C8 only — see the WP-KILL '
    'report\'s commitment-point observability table). Every other '
    'commitment point already has a native durable record (server table, '
    'coordinator/payer journal, or wallet balance/UTXO state); assert '
    'against that directly instead of adding a seam for it.',
  );
  final payload = <String, Object?>{
    'step': step,
    'cid': cid,
    'status': status,
    'ts': DateTime.now().toUtc().toIso8601String(),
    ...data,
  };
  final line = 'CHECKPOINT ${jsonEncode(payload)}';
  return redactor == null ? line : redactor(line);
}
