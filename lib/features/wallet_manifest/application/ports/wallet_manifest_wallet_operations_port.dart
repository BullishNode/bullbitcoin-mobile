import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

abstract class WalletManifestWalletOperationsPort {
  Future<List<Wallet>> getDefaultBitcoinWallets();

  Future<String> getSeedXprv({
    required String masterFingerprint,
    required Network network,
  });

  Future<List<Wallet>> getWallets({required bool sync});

  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonicPreview({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
  });

  Future<Seed> createSeedFromMnemonic({required List<String> mnemonicWords});

  Future<Wallet> createWallet({
    required Seed seed,
    required Network network,
    required ScriptType scriptType,
    required String label,
    required bool sync,
  });

  Future<void> deleteWallet({required String walletId});

  Future<void> recordMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
    required String alias,
    required Bip85Usage usage,
  });

  Future<void> deleteMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
  });
}
