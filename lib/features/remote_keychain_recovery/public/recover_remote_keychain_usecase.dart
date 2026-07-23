import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

/// Silent, re-invocable entrypoint for remote keychain (manifest) wallet
/// recovery. It awaits the underlying bounded recovery and swallows every
/// failure so the caller can continue regardless of the outcome. Both the
/// onboarding recover flow and the RecoverBull vault restore drive it, and a
/// settings page can call it again later to retry manually.
class RecoverRemoteKeychainUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const RecoverRemoteKeychainUsecase(this._remoteRecovery);

  /// Awaits recovery within its own time budget and never throws. Callers
  /// `await` this before they load the wallet inventory so restored manifest
  /// wallets are present on the very first load.
  Future<void> execute({required Set<String> defaultCreatedWalletIds}) =>
      _recover(defaultCreatedWalletIds);

  Future<void> _recover(Set<String> defaultCreatedWalletIds) async {
    try {
      final result = await _remoteRecovery.recover(
        defaultCreatedWalletIds: defaultCreatedWalletIds,
      );
      if (result.status != RemoteKeychainRecoveryStatus.noBackup &&
          result.status != RemoteKeychainRecoveryStatus.nothingToRestore &&
          result.status != RemoteKeychainRecoveryStatus.restored) {
        log.warning(
          'Optional remote keychain recovery did not complete: '
          '${result.status.name}',
        );
      }
    } on Exception catch (error, stack) {
      log.warning(
        'Optional remote keychain recovery failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
