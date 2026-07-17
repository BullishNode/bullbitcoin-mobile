import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

/// Maps the app's real [RemoteKeychainRecoveryStatus] onto the engine's
/// provider-agnostic [ExpectedRecoveryClass] so the analytic oracle
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.3 step 6) can score a live run without
/// importing app types into the pure-Dart engine.
///
/// PORT NOTE (2026-07-17, re-derived against the current PR #132 tip): the
/// app's recovery status model changed shape since this mapping was first
/// written. The old 16-value `RemoteKeychainRecoveryStatus` (idle/checking/
/// restoring/requiresRelayDisclosure/skipped + 11 terminal values including
/// `failed`) has been replaced by an 8-value, ALWAYS-terminal enum with no
/// relay-consent gate: `noBackup, unavailable, invalid, tooLarge,
/// newerVersion, conflict, restored, partiallyRestored`. There is no longer a
/// 1:1 mapping onto the engine's 9-value [ExpectedRecoveryClass] — several new
/// values collapse onto the closest surviving oracle class:
///   - `noBackup` -> `nothingToRestore` (no backup exists to restore).
///   - `unavailable` -> `relaysUnavailable` (remote/backup transport down).
///   - `invalid` -> `restoreFailed` (a backup existed but failed integrity/
///     authenticity checks — same bucket the old `restoreFailed` covered).
///   - `tooLarge` -> `restoreFailed` (a backup existed but exceeded a decode
///     bound; a real failure to restore, not "nothing to restore").
///   - `newerVersion` -> `unsupportedNewerManifest` (direct carry-over).
///   - `conflict` -> `restoreFailed` (a CAS/generation race prevented the
///     fetch from completing; the run did not restore).
/// This folding is coarser than the old mapping and should be revisited once
/// WP-A3's ledger assigns real ids to the M4 recovery transitions — some of
/// these folds may deserve their own oracle class rather than sharing
/// `restoreFailed`. Flag for Fable review before this scores anything money-
/// bearing.
ExpectedRecoveryClass mapRecoveryStatus(RemoteKeychainRecoveryStatus status) {
  switch (status) {
    case RemoteKeychainRecoveryStatus.restored:
      return ExpectedRecoveryClass.restored;
    case RemoteKeychainRecoveryStatus.partiallyRestored:
      return ExpectedRecoveryClass.partiallyRestored;
    case RemoteKeychainRecoveryStatus.noBackup:
      return ExpectedRecoveryClass.nothingToRestore;
    case RemoteKeychainRecoveryStatus.unavailable:
      return ExpectedRecoveryClass.relaysUnavailable;
    case RemoteKeychainRecoveryStatus.invalid:
    case RemoteKeychainRecoveryStatus.tooLarge:
    case RemoteKeychainRecoveryStatus.conflict:
      return ExpectedRecoveryClass.restoreFailed;
    case RemoteKeychainRecoveryStatus.newerVersion:
      return ExpectedRecoveryClass.unsupportedNewerManifest;
  }
}

/// Whether [status] is a terminal recovery verdict (the P1 totality check).
///
/// The new [RemoteKeychainRecoveryStatus] has no non-terminal member at all —
/// recovery is now a single synchronous call
/// (`RemoteKeychainRecoveryFacade.recover()`), not a staged cubit with
/// idle/checking/restoring/requiresRelayDisclosure states — so every value is
/// terminal by construction. Kept as a function (always `true`) so callers
/// written against the old staged model do not need a separate code path, and
/// so a future reintroduction of a non-terminal member fails loudly here
/// instead of silently.
bool isTerminalRecoveryStatus(RemoteKeychainRecoveryStatus status) => true;
