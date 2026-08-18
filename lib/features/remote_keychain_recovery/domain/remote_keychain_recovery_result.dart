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
