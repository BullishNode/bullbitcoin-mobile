import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:qa_matrix_engine/qa_matrix_engine.dart';

/// Maps the app's real [RemoteKeychainRecoveryStatus] onto the engine's
/// provider-agnostic [ExpectedRecoveryClass] so the analytic oracle
/// (GETPAID-APP-E2E-FAILURE-MATRIX §5.3 step 6) can score a live run without
/// importing app types into the pure-Dart engine.
///
/// `noManifestFound` folds onto [ExpectedRecoveryClass.nothingToRestore]: both
/// are "the seed-derived coordinate is empty" from the oracle's point of view;
/// the app keeps them distinct at the UI layer, but the money-safety oracle
/// only cares that neither is a false "restored". The non-terminal statuses
/// (idle/checking/restoring) and the interaction-gate statuses
/// (requiresRelayDisclosure/skipped) return null — a run that ends there never
/// reached a recovery verdict, which P1 (totality) flags.
ExpectedRecoveryClass? mapRecoveryStatus(RemoteKeychainRecoveryStatus status) {
  switch (status) {
    case RemoteKeychainRecoveryStatus.restored:
      return ExpectedRecoveryClass.restored;
    case RemoteKeychainRecoveryStatus.partiallyRestored:
      return ExpectedRecoveryClass.partiallyRestored;
    case RemoteKeychainRecoveryStatus.olderManifestAvailable:
      return ExpectedRecoveryClass.olderManifestAvailable;
    case RemoteKeychainRecoveryStatus.nothingToRestore:
    case RemoteKeychainRecoveryStatus.noManifestFound:
      return ExpectedRecoveryClass.nothingToRestore;
    case RemoteKeychainRecoveryStatus.unsupportedNewerManifest:
      return ExpectedRecoveryClass.unsupportedNewerManifest;
    case RemoteKeychainRecoveryStatus.relaysUnavailable:
      return ExpectedRecoveryClass.relaysUnavailable;
    case RemoteKeychainRecoveryStatus.noRecoverableManifest:
      return ExpectedRecoveryClass.noRecoverableManifest;
    case RemoteKeychainRecoveryStatus.restoreFailed:
      return ExpectedRecoveryClass.restoreFailed;
    case RemoteKeychainRecoveryStatus.defaultWalletUnavailable:
      return ExpectedRecoveryClass.defaultWalletUnavailable;
    case RemoteKeychainRecoveryStatus.idle:
    case RemoteKeychainRecoveryStatus.checking:
    case RemoteKeychainRecoveryStatus.restoring:
    case RemoteKeychainRecoveryStatus.requiresRelayDisclosure:
    case RemoteKeychainRecoveryStatus.skipped:
    case RemoteKeychainRecoveryStatus.failed:
      return null;
  }
}

/// Whether [status] is a terminal recovery verdict (the P1 totality check).
bool isTerminalRecoveryStatus(RemoteKeychainRecoveryStatus status) {
  switch (status) {
    case RemoteKeychainRecoveryStatus.idle:
    case RemoteKeychainRecoveryStatus.checking:
    case RemoteKeychainRecoveryStatus.restoring:
      return false;
    case RemoteKeychainRecoveryStatus.requiresRelayDisclosure:
    case RemoteKeychainRecoveryStatus.olderManifestAvailable:
    case RemoteKeychainRecoveryStatus.restored:
    case RemoteKeychainRecoveryStatus.partiallyRestored:
    case RemoteKeychainRecoveryStatus.nothingToRestore:
    case RemoteKeychainRecoveryStatus.restoreFailed:
    case RemoteKeychainRecoveryStatus.skipped:
    case RemoteKeychainRecoveryStatus.noManifestFound:
    case RemoteKeychainRecoveryStatus.relaysUnavailable:
    case RemoteKeychainRecoveryStatus.noRecoverableManifest:
    case RemoteKeychainRecoveryStatus.unsupportedNewerManifest:
    case RemoteKeychainRecoveryStatus.defaultWalletUnavailable:
    case RemoteKeychainRecoveryStatus.failed:
      return true;
  }
}
