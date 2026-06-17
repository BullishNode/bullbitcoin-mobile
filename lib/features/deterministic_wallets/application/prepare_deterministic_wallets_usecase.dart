import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/domain/derive_bip85_mnemonic_at_index_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/wallet_metadata_service.dart';
import 'package:bb_mobile/features/deterministic_wallets/application/application_errors.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

typedef DeterministicWalletMetadataDeriver =
    Future<WalletMetadataModel> Function({
      required Seed seed,
      required Network network,
      required ScriptType scriptType,
      String? label,
      required bool isDefault,
    });

class PrepareDeterministicWalletsUsecase {
  final DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase _deriveBip85;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final DeterministicWalletMetadataDeriver _deriveWalletMetadata;

  PrepareDeterministicWalletsUsecase({
    required this._deriveBip85,
    required this._walletRepository,
    required this._seedRepository,
    DeterministicWalletMetadataDeriver? deriveWalletMetadata,
  }) : _deriveWalletMetadata =
           deriveWalletMetadata ?? WalletMetadataService.deriveFromSeed;

  Future<PreparedDeterministicWallets> execute(
    DeterministicWalletsRequest request,
  ) async {
    _validateRequest(request);
    final derived = await _deriveBip85.execute(
      index: request.bip85Index,
      alias: request.bip85Alias,
      environment: request.environment,
    );
    final childSeedPreview = _seedFromMnemonic(derived.mnemonic);

    final results = <PreparedDeterministicWallet>[];
    var seedStoredDuringAttempt = false;
    MnemonicSeed? childSeed;
    try {
      for (final spec in request.walletSpecs) {
        final expectedMetadata = await _deriveWalletMetadata(
          seed: childSeedPreview,
          network: spec.network,
          scriptType: spec.scriptType,
          label: spec.label,
          isDefault: spec.isDefault,
        );
        final existing = await _walletRepository.getWallet(expectedMetadata.id);
        if (existing != null) {
          _throwIfWalletDoesNotMatchExpected(
            wallet: existing,
            spec: spec,
            expectedExternalDescriptor:
                expectedMetadata.externalPublicDescriptor,
            expectedInternalDescriptor:
                expectedMetadata.internalPublicDescriptor,
          );
          results.add(
            PreparedDeterministicWallet(
              specId: spec.id,
              wallet: existing,
              created: false,
            ),
          );
          continue;
        }

        childSeed ??= await _ensureChildSeedStored(
          childSeedPreview,
          onStored: () => seedStoredDuringAttempt = true,
        );
        final created = await _walletRepository.createWallet(
          seed: childSeed,
          network: spec.network,
          scriptType: spec.scriptType,
          isDefault: spec.isDefault,
          sync: spec.sync,
          label: spec.label,
        );
        results.add(
          PreparedDeterministicWallet(
            specId: spec.id,
            wallet: created,
            created: true,
          ),
        );
      }
    } catch (e, stack) {
      await _rollbackCreatedWalletsBestEffort(results);
      if (seedStoredDuringAttempt &&
          results.every((wallet) => wallet.created)) {
        await _deleteChildSeedBestEffort(childSeedPreview);
      }
      log.warning(
        'Deterministic wallet materialization failed',
        error: e,
        trace: stack,
      );
      rethrow;
    }

    return PreparedDeterministicWallets(
      wallets: results,
      childSeedFingerprint: childSeedPreview.masterFingerprint,
      childSeedStoredDuringAttempt: seedStoredDuringAttempt,
    );
  }

  Future<void> rollbackCreatedWallets(
    PreparedDeterministicWallets result,
  ) async {
    for (final prepared in result.wallets.where((wallet) => wallet.created)) {
      await _walletRepository.deleteWallet(walletId: prepared.wallet.id);
    }
    if (result.shouldDeleteChildSeedOnRollback) {
      await _seedRepository.delete(result.childSeedFingerprint);
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
    final exists = await _seedRepository.exists(
      childSeedPreview.masterFingerprint,
    );
    if (exists) return childSeedPreview;

    onStored();
    return _seedRepository.createFromMnemonic(
      mnemonicWords: childSeedPreview.mnemonicWords,
      passphrase: childSeedPreview.passphrase,
    );
  }

  void _throwIfWalletDoesNotMatchExpected({
    required Wallet wallet,
    required DeterministicWalletSpec spec,
    required String expectedExternalDescriptor,
    required String expectedInternalDescriptor,
  }) {
    if (wallet.scriptType != spec.scriptType ||
        wallet.externalPublicDescriptor != expectedExternalDescriptor ||
        wallet.internalPublicDescriptor != expectedInternalDescriptor) {
      throw DeterministicWalletException.walletMismatch(
        'Existing deterministic wallet metadata does not match expected '
        'descriptors for ${spec.id}',
      );
    }
  }

  Future<void> _rollbackCreatedWalletsBestEffort(
    List<PreparedDeterministicWallet> wallets,
  ) async {
    for (final prepared in wallets.where((wallet) => wallet.created)) {
      try {
        await _walletRepository.deleteWallet(walletId: prepared.wallet.id);
      } catch (e, stack) {
        log.warning(
          'Deterministic wallet rollback failed',
          error: e,
          trace: stack,
        );
      }
    }
  }

  Future<void> _deleteChildSeedBestEffort(MnemonicSeed childSeed) async {
    try {
      await _seedRepository.delete(childSeed.masterFingerprint);
    } catch (e, stack) {
      log.warning(
        'Deterministic wallet child seed rollback failed',
        error: e,
        trace: stack,
      );
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
