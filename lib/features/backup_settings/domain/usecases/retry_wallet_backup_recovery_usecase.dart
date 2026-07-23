import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/remote_keychain_recovery_facade.dart';

final class RetryWalletBackupRecoveryUsecase {
  final GetWalletsUsecase _getWallets;
  final RemoteKeychainRecoveryFacade _remoteRecovery;

  const RetryWalletBackupRecoveryUsecase(
    this._getWallets,
    this._remoteRecovery,
  );

  Future<RemoteKeychainRecoveryResult> execute() async {
    final defaultWallets = await _getWallets.execute(onlyDefaults: true);
    return _remoteRecovery.recover(
      defaultCreatedWalletIds: defaultWallets
          .map((wallet) => wallet.id)
          .toSet(),
    );
  }
}
