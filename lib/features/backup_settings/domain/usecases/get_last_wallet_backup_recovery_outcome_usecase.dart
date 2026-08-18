import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

enum WalletBackupRecoveryOutcomeStatus {
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

WalletBackupRecoveryOutcomeStatus mapRemoteRecoveryStatus(
  RemoteKeychainRecoveryStatus status,
) => switch (status) {
  RemoteKeychainRecoveryStatus.noBackup =>
    WalletBackupRecoveryOutcomeStatus.noBackup,
  RemoteKeychainRecoveryStatus.nothingToRestore =>
    WalletBackupRecoveryOutcomeStatus.nothingToRestore,
  RemoteKeychainRecoveryStatus.unavailable =>
    WalletBackupRecoveryOutcomeStatus.unavailable,
  RemoteKeychainRecoveryStatus.invalid =>
    WalletBackupRecoveryOutcomeStatus.invalid,
  RemoteKeychainRecoveryStatus.tooLarge =>
    WalletBackupRecoveryOutcomeStatus.tooLarge,
  RemoteKeychainRecoveryStatus.newerVersion =>
    WalletBackupRecoveryOutcomeStatus.newerVersion,
  RemoteKeychainRecoveryStatus.conflict =>
    WalletBackupRecoveryOutcomeStatus.conflict,
  RemoteKeychainRecoveryStatus.localFailure =>
    WalletBackupRecoveryOutcomeStatus.localFailure,
  RemoteKeychainRecoveryStatus.restored =>
    WalletBackupRecoveryOutcomeStatus.restored,
  RemoteKeychainRecoveryStatus.partiallyRestored =>
    WalletBackupRecoveryOutcomeStatus.partiallyRestored,
  RemoteKeychainRecoveryStatus.timedOut =>
    WalletBackupRecoveryOutcomeStatus.timedOut,
};

/// Backup Settings-owned projection of the remote recovery audit record.
///
/// The remote feature's entity never crosses into Backup Settings
/// presentation state. That keeps this feature stable if recovery changes its
/// internal persistence model.
final class WalletBackupRecoveryOutcome {
  final WalletBackupRecoveryOutcomeStatus status;
  final int atUnix;
  final int restoredCount;
  final int failedCount;

  const WalletBackupRecoveryOutcome({
    required this.status,
    required this.atUnix,
    required this.restoredCount,
    required this.failedCount,
  });
}

/// Backup Settings-owned view of the last remote recovery attempt.
///
/// Keeping this adapter here means the presentation layer depends only on its
/// own use cases while the cross-feature call remains behind Remote Recovery's
/// public facade.
final class GetLastWalletBackupRecoveryOutcomeUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const GetLastWalletBackupRecoveryOutcomeUsecase(this._remoteRecovery);

  Future<WalletBackupRecoveryOutcome?> execute() async {
    final outcome = await _remoteRecovery.getLastOutcome();
    if (outcome == null) return null;
    return WalletBackupRecoveryOutcome(
      status: mapRemoteRecoveryStatus(outcome.status),
      atUnix: outcome.atUnix,
      restoredCount: outcome.restoredCount,
      failedCount: outcome.failedCount,
    );
  }
}
