import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/lightning_address/application/ports/lightning_address_default_wallet_xprv_port.dart';

class DefaultWalletXprvAdapter
    implements LightningAddressDefaultWalletXprvPort {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  const DefaultWalletXprvAdapter({
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
  }) : _walletRepository = walletRepository,
       _seedRepository = seedRepository;

  @override
  Future<String> deriveDefaultWalletXprv() async {
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw StateError('No default Bitcoin wallet found');
    final defaultWallet = wallets.first;
    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    return Bip32Derivation.getXprvFromSeed(seed.bytes, defaultWallet.network);
  }
}
