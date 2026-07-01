enum RemoteKeychainRecoveryStatus {
  idle,
  requiresRelayDisclosure,
  checking,
  olderManifestAvailable,
  restoring,
  restored,
  partiallyRestored,
  restoreFailed,
  skipped,
  noManifestFound,
  relaysUnavailable,
  noRecoverableManifest,
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
  final Object? error;

  const RemoteKeychainRecoveryState({
    this.status = RemoteKeychainRecoveryStatus.idle,
    this.restoredCount = 0,
    this.failedCount = 0,
    this.hasProductReactivationRequired = false,
    this.newestEventCreatedAt,
    this.selectedEventCreatedAt,
    this.error,
  });
}
