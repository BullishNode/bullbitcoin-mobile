import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';

class DeleteCreatedExternalReceiveWalletUsecase {
  final GetExternalReceiveWalletUsecase _getWallet;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final Bip85Repository _bip85Repository;
  final WalletManifestFacade _walletManifest;

  const DeleteCreatedExternalReceiveWalletUsecase({
    required GetExternalReceiveWalletUsecase getWallet,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required Bip85Repository bip85Repository,
    required WalletManifestFacade walletManifest,
  }) : _getWallet = getWallet,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _bip85Repository = bip85Repository,
       _walletManifest = walletManifest;

  Future<void> execute({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    required ExternalReceiveWalletAccountKey accountKey,
    required String expectedWalletId,
  }) async {
    final wallet = await _getWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
    );
    if (wallet == null || wallet.id != expectedWalletId) return;

    await _walletRepository.deleteWallet(walletId: wallet.id);
    await _deleteOriginBestEffort(wallet.id);
    await _deleteBip85DerivationBestEffort(
      environment: environment,
      accountKey: accountKey,
    );
  }

  Future<void> _deleteOriginBestEffort(String walletId) async {
    try {
      await _walletManifest.deleteOrigin(walletId: walletId);
    } catch (e) {
      log.warning('External receive wallet origin cleanup failed', error: e);
    }
  }

  Future<void> _deleteBip85DerivationBestEffort({
    required Environment environment,
    required ExternalReceiveWalletAccountKey accountKey,
  }) async {
    try {
      final defaultWallets = await _walletRepository.getWallets(
        environment: environment,
        onlyDefaults: true,
        onlyBitcoin: true,
      );
      if (defaultWallets.isEmpty) return;

      final defaultWallet = defaultWallets.first;
      final derivationPath = Bip85DerivationPath.mnemonic12(
        index: accountKey.bip85Index,
      ).value;
      final hasSiblingOrigin = await _hasRemainingOriginForDerivation(
        derivationPath,
      );
      if (hasSiblingOrigin) return;

      final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
      final xprv = Bip32Derivation.getXprvFromSeed(
        seed.bytes,
        defaultWallet.network,
      );
      await _bip85Repository.deleteMnemonicDerivation(
        xprvBase58: xprv,
        derivationPath: derivationPath,
      );
    } catch (e) {
      log.warning(
        'External receive wallet BIP85 derivation cleanup failed',
        error: e,
      );
    }
  }

  Future<bool> _hasRemainingOriginForDerivation(String derivationPath) async {
    try {
      final origins = await _walletManifest.fetchOrigins();
      return origins.any(
        (origin) => origin.bip85DerivationPath.value == derivationPath,
      );
    } catch (e) {
      log.warning(
        'External receive wallet origin lookup failed during BIP85 cleanup',
        error: e,
      );
      return true;
    }
  }
}
