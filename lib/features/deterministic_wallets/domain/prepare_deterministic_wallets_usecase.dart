import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/domain/bip85_errors.dart';
import 'package:bb_mobile/core/bip85/domain/derive_bip85_mnemonic_at_index_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/repositories/deterministic_wallet_repository.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class PrepareDeterministicWalletsUsecase {
  final DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase _deriveBip85;
  final DeterministicWalletRepository _walletRepository;

  PrepareDeterministicWalletsUsecase({
    required this._deriveBip85,
    required this._walletRepository,
  });

  Future<PreparedDeterministicWallets> execute(
    DeterministicWalletsRequest request,
  ) async {
    _validateRequest(request);
    final ({
      String derivation,
      bip39.Mnemonic mnemonic,
      String parentFingerprint,
    })
    derived;
    try {
      derived = await _deriveBip85.execute(
        index: request.bip85Index,
        alias: request.bip85Alias,
        environment: request.environment,
      );
    } on Bip85DerivationConflictException catch (e) {
      throw DeterministicWalletException.derivationConflict(e.message);
    }
    final childSeedPreview = _seedFromMnemonic(derived.mnemonic);

    final results = <PreparedDeterministicWallet>[];
    var seedStoredDuringAttempt = false;
    MnemonicSeed? childSeed;
    try {
      for (final spec in request.walletSpecs) {
        final existing = await _walletRepository.getMatchingWallet(
          seedPreview: childSeedPreview,
          spec: spec,
        );
        if (existing != null) {
          results.add(existing);
          continue;
        }

        childSeed ??= await _ensureChildSeedStored(
          childSeedPreview,
          onStored: () => seedStoredDuringAttempt = true,
        );
        final created = await _walletRepository.createWallet(
          childSeed: childSeed,
          spec: spec,
        );
        results.add(created);
      }
    } catch (e, stack) {
      final cleanupFailures = await _rollbackCreatedWallets(results);
      if (seedStoredDuringAttempt &&
          results.every((wallet) => wallet.created) &&
          cleanupFailures.isEmpty &&
          !await _deleteChildSeed(childSeedPreview.masterFingerprint)) {
        cleanupFailures.add(childSeedPreview.masterFingerprint);
      }
      log.warning(
        'Deterministic wallet materialization failed',
        error: e,
        trace: stack,
      );
      if (cleanupFailures.isNotEmpty) {
        throw DeterministicWalletException.rollbackFailed();
      }
      rethrow;
    }

    return PreparedDeterministicWallets(
      wallets: results,
      derivationPath: derived.derivation,
      parentFingerprint: derived.parentFingerprint,
      childSeedFingerprint: childSeedPreview.masterFingerprint,
      childSeedStoredDuringAttempt: seedStoredDuringAttempt,
    );
  }

  Future<void> rollbackCreatedWallets(
    PreparedDeterministicWallets result,
  ) async {
    final cleanupFailures = await _rollbackCreatedWallets(result.wallets);
    if (result.shouldDeleteChildSeedOnRollback &&
        cleanupFailures.isEmpty &&
        !await _deleteChildSeed(result.childSeedFingerprint)) {
      cleanupFailures.add(result.childSeedFingerprint);
    }
    if (cleanupFailures.isNotEmpty) {
      throw DeterministicWalletException.rollbackFailed();
    }
  }

  void _validateRequest(DeterministicWalletsRequest request) {
    if (request.bip85Index < 0) {
      throw DeterministicWalletException.invalidRequest(
        'BIP85 index must be zero or greater',
      );
    }
    if (request.bip85Alias.trim().isEmpty) {
      throw DeterministicWalletException.invalidRequest(
        'BIP85 alias is required',
      );
    }
    if (request.walletSpecs.isEmpty) {
      throw DeterministicWalletException.invalidRequest(
        'At least one wallet spec is required',
      );
    }

    final specIds = <String>{};
    for (final spec in request.walletSpecs) {
      final specId = spec.id.trim();
      if (specId.isEmpty) {
        throw DeterministicWalletException.invalidRequest(
          'Wallet spec ID is required',
        );
      }
      if (!specIds.add(specId)) {
        throw DeterministicWalletException.invalidRequest(
          'Wallet spec IDs must be unique',
        );
      }
    }
  }

  Future<MnemonicSeed> _ensureChildSeedStored(
    MnemonicSeed childSeedPreview, {
    required void Function() onStored,
  }) async {
    final exists = await _walletRepository.childSeedExists(
      childSeedPreview.masterFingerprint,
    );
    if (exists) return childSeedPreview;

    onStored();
    return _walletRepository.storeChildSeed(childSeedPreview);
  }

  Future<List<String>> _rollbackCreatedWallets(
    List<PreparedDeterministicWallet> wallets,
  ) async {
    final failures = <String>[];
    for (final prepared in wallets.where((wallet) => wallet.created)) {
      try {
        await _walletRepository.deleteWallet(prepared.walletId);
      } catch (e, stack) {
        failures.add(prepared.walletId);
        log.warning(
          'Deterministic wallet rollback failed',
          error: e,
          trace: stack,
        );
      }
    }
    return failures;
  }

  Future<bool> _deleteChildSeed(String fingerprint) async {
    final result = await _walletRepository.deleteChildSeed(fingerprint);
    switch (result) {
      case Ok():
        return true;
      case Err(:final failure):
        log.warning(
          'Deterministic wallet child seed rollback failed',
          error: failure,
        );
        return false;
    }
  }

  MnemonicSeed _seedFromMnemonic(bip39.Mnemonic mnemonic) {
    final seedBytes = Uint8List.fromList(mnemonic.seed);
    return Seed.mnemonic(
          mnemonicWords: mnemonic.words,
          bytes: seedBytes,
          masterFingerprint: bip32.Bip32Keys.fromSeed(
            seedBytes,
          ).fingerprint.toHexString(),
        )
        as MnemonicSeed;
  }
}
