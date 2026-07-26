import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:meta/meta.dart';

/// RecoverBull-owned boundary for optional remote recovery.
class RecoverBullRemoteKeychainUsecase {
  final Future<RemoteKeychainRecoveryResult> Function({
    Set<String> defaultCreatedWalletIds,
  })
  _recover;

  RecoverBullRemoteKeychainUsecase(RemoteKeychainRecoveryFacade recovery)
    : _recover = recovery.recover;

  @visibleForTesting
  RecoverBullRemoteKeychainUsecase.withRecover(this._recover);

  Future<void> execute({required Set<String> defaultCreatedWalletIds}) async {
    try {
      final result = await _recover(
        defaultCreatedWalletIds: defaultCreatedWalletIds,
      );
      if (result.status != RemoteKeychainRecoveryStatus.noBackup &&
          result.status != RemoteKeychainRecoveryStatus.nothingToRestore &&
          result.status != RemoteKeychainRecoveryStatus.restored) {
        log.warning(
          'Optional RecoverBull remote recovery did not complete: '
          '${result.status.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Optional RecoverBull remote recovery failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
