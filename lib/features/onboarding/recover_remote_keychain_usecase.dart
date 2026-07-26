import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

/// Onboarding-owned boundary for optional remote recovery.
///
/// Recovery is awaited before the first wallet inventory load, but every
/// failure remains non-fatal because the default wallets already exist.
class RecoverRemoteKeychainUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const RecoverRemoteKeychainUsecase(this._remoteRecovery);

  Future<void> execute({required Set<String> defaultCreatedWalletIds}) async {
    try {
      final result = await _remoteRecovery.recover(
        defaultCreatedWalletIds: defaultCreatedWalletIds,
      );
      if (result.status != RemoteKeychainRecoveryStatus.noBackup &&
          result.status != RemoteKeychainRecoveryStatus.nothingToRestore &&
          result.status != RemoteKeychainRecoveryStatus.restored) {
        log.warning(
          'Optional onboarding remote recovery did not complete: '
          '${result.status.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Optional onboarding remote recovery failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
