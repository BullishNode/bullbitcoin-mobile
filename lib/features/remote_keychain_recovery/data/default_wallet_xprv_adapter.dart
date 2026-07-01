// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';

class RemoteKeychainRecoveryDefaultWalletXprvAdapter
    implements RemoteKeychainRecoveryDefaultWalletXprvPort {
  final GetSettingsUsecase _getSettings;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const RemoteKeychainRecoveryDefaultWalletXprvAdapter({
    required GetSettingsUsecase getSettings,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _getSettings = getSettings,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  @override
  Future<RemoteKeychainRecoveryDefaultWalletXprv>
  deriveDefaultWalletXprv() async {
    final settings = await _getSettings.execute();
    final wallets = await _walletRepository.getWallets(
      environment: settings.environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw const RemoteKeychainRecoveryException(
        RemoteKeychainRecoveryErrorKind.defaultWalletUnavailable,
      );
    }
    final defaultWallet = wallets.first;
    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return RemoteKeychainRecoveryDefaultWalletXprv(
      xprvBase58: Bip32Derivation.getXprvFromSeed(
        seed.bytes,
        defaultWallet.network,
      ),
      parentFingerprint: defaultWallet.masterFingerprint,
    );
  }
}
