enum RemoteKeychainRecoveryStatus {
  noBackup,
  nothingToRestore,
  unavailable,
  invalid,
  tooLarge,
  newerVersion,
  conflict,
  localFailure,
  restored,
  partiallyRestored,
  // The recovery ran past its total time budget before it could finish. Treated
  // exactly like `unavailable` by callers: keep the default wallets, log a
  // sanitized outcome, continue silently.
  timedOut,
}

final class RemoteKeychainRecoveryResult {
  final RemoteKeychainRecoveryStatus status;
  final int restoredCount;
  final int failedCount;
  final List<String> createdWalletIds;
  final String? metadataPayload;

  const RemoteKeychainRecoveryResult({
    required this.status,
    this.restoredCount = 0,
    this.failedCount = 0,
    this.createdWalletIds = const [],
    this.metadataPayload,
  });
}
