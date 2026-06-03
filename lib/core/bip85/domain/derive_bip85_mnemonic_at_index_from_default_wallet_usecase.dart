import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_errors.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase {
  final Bip85Repository _bip85Repository;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;

  DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase({
    required this._bip85Repository,
    required this._walletRepository,
    required this._seedRepository,
  });

  Future<
    ({String derivation, bip39.Mnemonic mnemonic, String parentFingerprint})
  >
  execute({
    required int index,
    required String alias,
    Environment? environment,
    bip39.MnemonicLength length = bip39.MnemonicLength.words12,
  }) async {
    final wallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw Bip85NoDefaultWalletException();
    final defaultWallet = wallets.first;

    final defaultSeed = await _seedRepository.get(
      defaultWallet.masterFingerprint,
    );

    final xprv = Bip32Derivation.getXprvFromSeed(
      defaultSeed.bytes,
      defaultWallet.network,
    );

    final preview = await _bip85Repository.deriveMnemonicPreview(
      xprvBase58: xprv,
      length: length,
      index: index,
    );
    final existing = await _bip85Repository.fetch(preview.derivation);
    if (existing != null) {
      _throwIfIncompatibleExistingDerivation(
        existing,
        xprvBase58: xprv,
        alias: alias,
      );
      return (
        derivation: preview.derivation,
        mnemonic: preview.mnemonic,
        parentFingerprint: defaultWallet.masterFingerprint,
      );
    }

    final derived = await _bip85Repository.deriveMnemonic(
      xprvBase58: xprv,
      length: length,
      index: index,
      alias: alias,
    );
    return (
      derivation: derived.derivation,
      mnemonic: derived.mnemonic,
      parentFingerprint: defaultWallet.masterFingerprint,
    );
  }

  void _throwIfIncompatibleExistingDerivation(
    Bip85DerivationEntity existing, {
    required String xprvBase58,
    required String alias,
  }) {
    final expectedFingerprint = _bip85Repository.fingerprintFromXprv(
      xprvBase58,
    );
    if (existing.xprvFingerprint != expectedFingerprint) {
      throw Bip85DerivationConflictException(
        'BIP85 derivation already exists for a different root fingerprint',
      );
    }
    if (existing.application != Bip85Application.bip39) {
      throw Bip85DerivationConflictException(
        'BIP85 derivation already exists for a different application',
      );
    }
    if (existing.alias != alias) {
      throw Bip85DerivationConflictException(
        'BIP85 derivation already exists with a different alias',
      );
    }
  }
}
