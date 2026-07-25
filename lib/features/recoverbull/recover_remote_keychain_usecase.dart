import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';
import 'package:meta/meta.dart';

final class RecoverBullRemoteKeychainUsecase {
  final Future<RemoteKeychainRecoveryResult> Function() _recover;

  RecoverBullRemoteKeychainUsecase(RemoteKeychainRecoveryFacade remoteRecovery)
    : _recover = remoteRecovery.recover;

  @visibleForTesting
  RecoverBullRemoteKeychainUsecase.withRecover(this._recover);

  /// Remote recovery is optional and bounded by its owning feature. It must
  /// finish before wallet inventory starts, but it must never block recovery
  /// from completing with the default wallets.
  Future<void> execute() async {
    try {
      final result = await _recover();
      if (result.status != RemoteKeychainRecoveryStatus.noBackup &&
          result.status != RemoteKeychainRecoveryStatus.nothingToRestore &&
          result.status != RemoteKeychainRecoveryStatus.restored) {
        log.warning(
          'Optional RecoverBull remote keychain recovery did not complete: '
          '${result.status.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Optional RecoverBull remote keychain recovery failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
