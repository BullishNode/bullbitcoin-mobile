import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/seed/domain/seed_failure.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/wallet_metadata_service.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/repositories/deterministic_wallet_repository.dart';

typedef DeterministicWalletMetadataDeriver =
    Future<WalletMetadataModel> Function({
      required Seed seed,
      required Network network,
      required ScriptType scriptType,
      String? label,
      required bool isDefault,
    });

class DeterministicWalletRepositoryImpl
    implements DeterministicWalletRepository {
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final DeterministicWalletMetadataDeriver _deriveWalletMetadata;

  DeterministicWalletRepositoryImpl({
    required this._walletRepository,
    required this._seedRepository,
    DeterministicWalletMetadataDeriver? deriveWalletMetadata,
  }) : _deriveWalletMetadata =
           deriveWalletMetadata ?? WalletMetadataService.deriveFromSeed;

  @override
  Future<PreparedDeterministicWallet?> getMatchingWallet({
    required MnemonicSeed seedPreview,
    required DeterministicWalletSpec spec,
  }) async {
    final expectedMetadata = await _deriveWalletMetadata(
      seed: seedPreview,
      network: spec.network,
      scriptType: spec.scriptType,
      label: spec.label,
      isDefault: spec.isDefault,
    );
    final existing = await _walletRepository.getWallet(expectedMetadata.id);
    if (existing == null) return null;
    _throwIfWalletDoesNotMatchExpected(
      wallet: existing,
      spec: spec,
      expectedExternalDescriptor: expectedMetadata.externalPublicDescriptor,
      expectedInternalDescriptor: expectedMetadata.internalPublicDescriptor,
    );
    return _toPreparedWallet(spec: spec, wallet: existing, created: false);
  }

  @override
  Future<bool> childSeedExists(String fingerprint) {
    return _seedRepository.exists(fingerprint);
  }

  @override
  Future<MnemonicSeed> storeChildSeed(MnemonicSeed seedPreview) {
    return _seedRepository.createFromMnemonic(
      mnemonicWords: seedPreview.mnemonicWords,
      passphrase: seedPreview.passphrase,
    );
  }

  @override
  Future<PreparedDeterministicWallet> createWallet({
    required MnemonicSeed childSeed,
    required DeterministicWalletSpec spec,
  }) async {
    final created = await _walletRepository.createWallet(
      seed: childSeed,
      network: spec.network,
      scriptType: spec.scriptType,
      isDefault: spec.isDefault,
      sync: spec.sync,
      label: spec.label,
    );
    return _toPreparedWallet(spec: spec, wallet: created, created: true);
  }

  @override
  Future<void> deleteWallet(String walletId) {
    return _walletRepository.deleteWallet(walletId: walletId);
  }

  @override
  Future<Result<void, SeedDeleteFailure>> deleteChildSeed(String fingerprint) {
    return _seedRepository.delete(fingerprint);
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

  PreparedDeterministicWallet _toPreparedWallet({
    required DeterministicWalletSpec spec,
    required Wallet wallet,
    required bool created,
  }) {
    return PreparedDeterministicWallet(
      specId: spec.id,
      walletId: wallet.id,
      network: wallet.network,
      scriptType: wallet.scriptType,
      label: wallet.label,
      externalPublicDescriptor: wallet.externalPublicDescriptor,
      internalPublicDescriptor: wallet.internalPublicDescriptor,
      created: created,
    );
  }
}
