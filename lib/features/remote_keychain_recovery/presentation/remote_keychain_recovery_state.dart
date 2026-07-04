import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';

enum RemoteKeychainRecoveryStatus {
  idle,
  requiresRelayDisclosure,
  checking,
  olderManifestAvailable,
  restoring,
  restored,
  partiallyRestored,
  nothingToRestore,
  restoreFailed,
  skipped,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
  unsupportedNewerManifest,
  defaultWalletUnavailable,
  failed,
}

class RemoteKeychainRecoveryState {
  final RemoteKeychainRecoveryStatus status;
  final int restoredCount;
  final int failedCount;
  final bool hasProductReactivationRequired;
  final int? newestEventCreatedAt;
  final int? selectedEventCreatedAt;

  /// True when the restored manifest was an older backup selected after the
  /// newest one could not be used - PR23's "restored from an older backup"
  /// confirmation reads this together with the timestamps (P22d, decision [D]).
  final bool isOlderRestore;

  /// The typed failure for a failed terminal state. Only the typed kind and its
  /// `toTranslated` message reach presentation; the raw cause stays in logs
  /// (P22b).
  final RemoteKeychainRecoveryException? failure;

  const RemoteKeychainRecoveryState({
    this.status = RemoteKeychainRecoveryStatus.idle,
    this.restoredCount = 0,
    this.failedCount = 0,
    this.hasProductReactivationRequired = false,
    this.newestEventCreatedAt,
    this.selectedEventCreatedAt,
    this.isOlderRestore = false,
    this.failure,
  });
}
