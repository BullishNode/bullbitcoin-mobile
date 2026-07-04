// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_settings_error.dart';

/// Derives the default-wallet xprv for the automated backup publish path.
///
/// The derivation is byte-for-byte identical to
/// `RemoteKeychainRecoveryDefaultWalletXprvAdapter` (the recovery fetch side).
/// The published author key MUST equal the key recovery fetches under, or the
/// backup is invisible to recovery (KC-4 obligation 4). The two adapters are
/// intentionally NOT consolidated in PR23; a parity test pins the equivalence
/// so a future drift on either side fails the build.
class GetPaidSettingsDefaultWalletXprvAdapter
    implements GetPaidSettingsDefaultWalletXprvPort {
  final GetSettingsUsecase _getSettings;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const GetPaidSettingsDefaultWalletXprvAdapter({
    required GetSettingsUsecase getSettings,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _getSettings = getSettings,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  @override
  Future<GetPaidSettingsDefaultWalletXprv> deriveDefaultWalletXprv() async {
    final settings = await _getSettings.execute();
    final wallets = await _walletRepository.getWallets(
      environment: settings.environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) {
      throw GetPaidSettingsStorageException();
    }
    final defaultWallet = wallets.first;
    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return GetPaidSettingsDefaultWalletXprv(
      xprvBase58: Bip32Derivation.getXprvFromSeed(
        seed.bytes,
        defaultWallet.network,
      ),
      parentFingerprint: defaultWallet.masterFingerprint,
    );
  }
}
