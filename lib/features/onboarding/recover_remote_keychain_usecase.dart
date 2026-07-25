import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

class RecoverRemoteKeychainUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const RecoverRemoteKeychainUsecase(this._remoteRecovery);

  /// Recovery is optional, bounded by its own deadline, and never prevents the
  /// seed-recovery flow from opening the default wallets.
  Future<void> execute() async {
    try {
      final result = await _remoteRecovery.recover();
      if (result.status != RemoteKeychainRecoveryStatus.noBackup &&
          result.status != RemoteKeychainRecoveryStatus.nothingToRestore &&
          result.status != RemoteKeychainRecoveryStatus.restored) {
        log.warning(
          'Optional remote keychain recovery did not complete: '
          '${result.status.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Optional remote keychain recovery failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
