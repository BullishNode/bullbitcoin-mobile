import 'package:bb_mobile/features/backup_settings/domain/usecases/get_last_wallet_backup_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

final class RetryWalletBackupRecoveryUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;
  final DateTime Function() _now;

  RetryWalletBackupRecoveryUsecase(
    this._remoteRecovery, {
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  Future<WalletBackupRecoveryOutcome> execute() async {
    final result = await _remoteRecovery.recover(
      // Manual retry runs against an already initialized wallet. Existing
      // defaults were not created by this recovery and must never authorize
      // recovered metadata to overwrite their local preferences.
      defaultCreatedWalletIds: const {},
    );
    return WalletBackupRecoveryOutcome(
      status: mapRemoteRecoveryStatus(result.status),
      atUnix: _now().millisecondsSinceEpoch ~/ 1000,
      restoredCount: result.restoredCount,
      failedCount: result.failedCount,
    );
  }
}
