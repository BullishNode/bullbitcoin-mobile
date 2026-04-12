import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class CreateLightningAddressWalletUsecase {

  final Bip85Repository _bip85Repository;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final GetLightningAddressWalletUsecase _getWallet;

  CreateLightningAddressWalletUsecase({
    required Bip85Repository bip85Repository,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required GetLightningAddressWalletUsecase getWallet,
  }) : _bip85Repository = bip85Repository,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _getWallet = getWallet;

  Future<Wallet> execute({required Environment environment}) async {
    final existing = await _getWallet.execute(environment: environment);
    if (existing != null) {
      throw LightningAddressWalletAlreadyExistsException();
    }

    // 1. Get default Bitcoin wallet to derive BIP85 child
    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw Exception('No default Bitcoin wallet found');
    final defaultWallet = wallets.first;

    // 2. Get seed and derive xprv
    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    final xprv = Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );

    final bip85 = await _bip85Repository.deriveMnemonic(
      xprvBase58: xprv,
      length: bip39.MnemonicLength.words12,
      index: lightningAddressWalletBip85Index,
      alias: lightningAddressWalletLabel,
    );

    // 4. Create seed from child mnemonic
    final childSeed = await _seedRepository.createFromMnemonic(
      mnemonicWords: bip85.mnemonic.words,
    );

    // 5. Create Liquid wallet from child seed
    final network = environment == Environment.mainnet
        ? Network.liquidMainnet
        : Network.liquidTestnet;

    return await _walletRepository.createWallet(
      seed: childSeed,
      network: network,
      scriptType: ScriptType.bip84,
      label: lightningAddressWalletLabel,
    );
  }
}
