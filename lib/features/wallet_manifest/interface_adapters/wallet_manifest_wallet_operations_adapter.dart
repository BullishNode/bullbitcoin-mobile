import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_wallet_operations_port.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class WalletManifestWalletOperationsAdapter
    implements WalletManifestWalletOperationsPort {
  final Bip85Repository _bip85Repository;
  final SeedRepository _seedRepository;
  final WalletRepository _walletRepository;
  final GetWalletsUsecase _getWallets;

  WalletManifestWalletOperationsAdapter({
    required Bip85Repository bip85Repository,
    required SeedRepository seedRepository,
    required WalletRepository walletRepository,
    required GetWalletsUsecase getWallets,
  }) : _bip85Repository = bip85Repository,
       _seedRepository = seedRepository,
       _walletRepository = walletRepository,
       _getWallets = getWallets;

  @override
  Future<List<Wallet>> getDefaultBitcoinWallets() {
    return _getWallets.execute(onlyDefaults: true, onlyBitcoin: true);
  }

  @override
  Future<String> getSeedXprv({
    required String masterFingerprint,
    required Network network,
  }) async {
    final seed = await _seedRepository.get(masterFingerprint);
    return Bip32Derivation.getXprvFromSeed(seed.bytes, network);
  }

  @override
  Future<List<Wallet>> getWallets({required bool sync}) {
    return _walletRepository.getWallets(sync: sync);
  }

  @override
  Future<({String derivation, bip39.Mnemonic mnemonic})> deriveMnemonicPreview({
    required String xprvBase58,
    required bip39.MnemonicLength length,
    required int index,
  }) {
    return _bip85Repository.deriveMnemonicPreview(
      xprvBase58: xprvBase58,
      length: length,
      index: index,
    );
  }

  @override
  Future<Seed> createSeedFromMnemonic({required List<String> mnemonicWords}) {
    return _seedRepository.createFromMnemonic(mnemonicWords: mnemonicWords);
  }

  @override
  Future<Wallet> createWallet({
    required Seed seed,
    required Network network,
    required ScriptType scriptType,
    required String label,
    required bool sync,
  }) {
    return _walletRepository.createWallet(
      seed: seed,
      network: network,
      scriptType: scriptType,
      label: label,
      sync: sync,
    );
  }

  @override
  Future<void> deleteWallet({required String walletId}) {
    return _walletRepository.deleteWallet(walletId: walletId);
  }

  @override
  Future<void> recordMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
    required String alias,
    required Bip85Usage usage,
  }) {
    return _bip85Repository.recordMnemonicDerivation(
      xprvBase58: xprvBase58,
      derivationPath: derivationPath,
      alias: alias,
      usage: usage,
    );
  }

  @override
  Future<void> deleteMnemonicDerivation({
    required String xprvBase58,
    required String derivationPath,
  }) {
    return _bip85Repository.deleteMnemonicDerivation(
      xprvBase58: xprvBase58,
      derivationPath: derivationPath,
    );
  }
}
