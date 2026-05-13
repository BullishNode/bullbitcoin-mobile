import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/get_bullnym_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_constants.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class CreateBullnymReceiveWalletUsecase {
  final Bip85Repository _bip85Repository;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final GetBullnymReceiveWalletUsecase _getWallet;

  CreateBullnymReceiveWalletUsecase({
    required Bip85Repository bip85Repository,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required GetBullnymReceiveWalletUsecase getWallet,
  }) : _bip85Repository = bip85Repository,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _getWallet = getWallet;

  Future<Wallet> execute({required Environment environment}) async {
    final existing = await _getWallet.execute(environment: environment);
    if (existing != null) {
      throw BullnymReceiveWalletAlreadyExistsException();
    }

    final wallets = await _walletRepository.getWallets(
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw LightningAddressNoDefaultWalletException();
    final defaultWallet = wallets.first;

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    final xprv = Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );

    final bip85 = await _bip85Repository.deriveMnemonic(
      xprvBase58: xprv,
      length: bip39.MnemonicLength.words12,
      index: bullnymReceiveWalletBip85Index,
      alias: bullnymReceiveWalletLabel,
    );

    final childSeed = await _seedRepository.createFromMnemonic(
      mnemonicWords: bip85.mnemonic.words,
    );

    final network = environment == Environment.mainnet
        ? Network.liquidMainnet
        : Network.liquidTestnet;

    return await _walletRepository.createWallet(
      seed: childSeed,
      network: network,
      scriptType: ScriptType.bip84,
      label: bullnymReceiveWalletLabel,
    );
  }
}
