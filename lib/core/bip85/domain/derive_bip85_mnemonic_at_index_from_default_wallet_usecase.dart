import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_errors.dart';
import 'package:bb_mobile/core/errors/bull_exception.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/result.dart';
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
    if (existing != null && _isForCurrentWallet(existing, xprvBase58: xprv)) {
      _throwIfIncompatibleExistingDerivation(existing, alias: alias);
      return (
        derivation: preview.derivation,
        mnemonic: preview.mnemonic,
        parentFingerprint: defaultWallet.masterFingerprint,
      );
    }
    // No row, or a stale row from a previous default wallet seed. A stale
    // row's mnemonic can no longer be derived from the current seed, so it
    // must not count as a conflict: re-derive and let storage replace it.

    final derivedResult = await _bip85Repository.deriveMnemonic(
      xprvBase58: xprv,
      length: length,
      index: index,
      alias: alias,
    );
    final derived = switch (derivedResult) {
      Ok(:final value) => value,
      Err(:final failure) => throw BullException(
        failure.logMessage ?? 'Failed to derive BIP85 mnemonic',
      ),
    };
    return (
      derivation: derived.derivation,
      mnemonic: derived.mnemonic,
      parentFingerprint: defaultWallet.masterFingerprint,
    );
  }

  bool _isForCurrentWallet(
    Bip85DerivationEntity existing, {
    required String xprvBase58,
  }) {
    final expectedFingerprint = _bip85Repository.fingerprintFromXprv(
      xprvBase58,
    );
    return existing.xprvFingerprint == expectedFingerprint;
  }

  void _throwIfIncompatibleExistingDerivation(
    Bip85DerivationEntity existing, {
    required String alias,
  }) {
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
