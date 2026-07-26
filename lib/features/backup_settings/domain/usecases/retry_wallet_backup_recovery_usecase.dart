import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

final class RetryWalletBackupRecoveryUsecase {
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const RetryWalletBackupRecoveryUsecase(this._remoteRecovery);

  Future<RemoteKeychainRecoveryResult> execute() => _remoteRecovery.recover(
    // Manual retry runs against an already initialized wallet. Existing
    // defaults were not created by this recovery and must never authorize
    // recovered metadata to overwrite their local preferences.
    defaultCreatedWalletIds: const {},
  );
}
