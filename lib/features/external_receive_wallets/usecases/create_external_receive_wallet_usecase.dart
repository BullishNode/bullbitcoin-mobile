import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/data/bip85_repository.dart';
import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/public/wallet_manifest.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

enum CreateExternalReceiveWalletStatus { created, repaired }

class CreateExternalReceiveWalletResult {
  final Wallet wallet;
  final CreateExternalReceiveWalletStatus status;

  const CreateExternalReceiveWalletResult({
    required this.wallet,
    required this.status,
  });
}

class CreateExternalReceiveWalletUsecase {
  final Bip85Repository _bip85Repository;
  final WalletRepository _walletRepository;
  final SeedRepository _seedRepository;
  final GetExternalReceiveWalletUsecase _getWallet;
  final WalletManifestFacade _walletManifest;

  CreateExternalReceiveWalletUsecase({
    required Bip85Repository bip85Repository,
    required WalletRepository walletRepository,
    required SeedRepository seedRepository,
    required GetExternalReceiveWalletUsecase getWallet,
    required WalletManifestFacade walletManifest,
  }) : _bip85Repository = bip85Repository,
       _walletRepository = walletRepository,
       _seedRepository = seedRepository,
       _getWallet = getWallet,
       _walletManifest = walletManifest;

  Future<Wallet> execute({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    ExternalReceiveWalletAccountKey? accountKey,
    bool publishManifest = true,
  }) async {
    final result = await executeWithResult(
      environment: environment,
      purpose: purpose,
      accountKey: accountKey,
      publishManifest: publishManifest,
    );
    return result.wallet;
  }

  Future<CreateExternalReceiveWalletResult> executeWithResult({
    required Environment environment,
    required ExternalReceiveWalletPurpose purpose,
    ExternalReceiveWalletAccountKey? accountKey,
    bool publishManifest = true,
  }) async {
    final key =
        accountKey ??
        purpose.liquidAccountKey(isTestnet: environment == Environment.testnet);
    if (key.purpose != purpose) {
      throw ArgumentError.value(
        accountKey,
        'accountKey',
        'account key purpose must match purpose',
      );
    }
    if (key.network.isTestnet != environment.isTestnet) {
      throw ArgumentError.value(
        accountKey,
        'accountKey',
        'account key network must match environment',
      );
    }
    final existing = await _getWallet.execute(
      environment: environment,
      purpose: purpose,
      accountKey: key,
    );
    if (existing != null) {
      throw ExternalReceiveWalletAlreadyExistsException();
    }

    final defaultWallet = await _getDefaultBitcoinWallet(environment);

    final seed = await _seedRepository.get(defaultWallet.masterFingerprint);
    final xprv = Bip32Derivation.getXprvFromSeed(
      seed.bytes,
      defaultWallet.network,
    );

    final preview = await _bip85Repository.deriveMnemonicPreview(
      xprvBase58: xprv,
      length: bip39.MnemonicLength.words12,
      index: key.bip85Index,
    );
    final childSeedPreview = _seedFromMnemonic(preview.mnemonic);

    final localExisting = await _findExistingLocalWallet(
      environment: environment,
      key: key,
      masterFingerprint: childSeedPreview.masterFingerprint,
    );
    if (localExisting != null) {
      await _recordDerivationOrThrow(
        wallet: localExisting,
        xprvBase58: xprv,
        derivationPath: preview.derivation,
        rollbackDerivationOnFailure: false,
        alias: key.walletLabel,
        repairedExistingWallet: true,
      );
      await _recordOriginOrThrow(
        wallet: localExisting,
        key: key,
        rootFingerprint: defaultWallet.masterFingerprint,
        repairedExistingWallet: true,
      );
      if (publishManifest) {
        await _publishManifestBestEffort();
      }
      return CreateExternalReceiveWalletResult(
        wallet: localExisting,
        status: CreateExternalReceiveWalletStatus.repaired,
      );
    }

    final childSeed = await _seedRepository.createFromMnemonic(
      mnemonicWords: preview.mnemonic.words,
    );

    final wallet = await _walletRepository.createWallet(
      seed: childSeed,
      network: key.network,
      scriptType: ScriptType.bip84,
      label: key.walletLabel,
    );

    await _recordDerivationOrThrow(
      wallet: wallet,
      xprvBase58: xprv,
      derivationPath: preview.derivation,
      rollbackDerivationOnFailure: true,
      alias: key.walletLabel,
      repairedExistingWallet: false,
    );
    await _recordOriginOrThrow(
      wallet: wallet,
      key: key,
      rootFingerprint: defaultWallet.masterFingerprint,
      xprvBase58: xprv,
      derivationPath: preview.derivation,
      repairedExistingWallet: false,
    );
    if (publishManifest) {
      await _publishManifestBestEffort();
    }

    return CreateExternalReceiveWalletResult(
      wallet: wallet,
      status: CreateExternalReceiveWalletStatus.created,
    );
  }

  Future<Wallet> _getDefaultBitcoinWallet(Environment environment) async {
    final wallets = await _walletRepository.getWallets(
      environment: environment,
      onlyDefaults: true,
      onlyBitcoin: true,
    );
    if (wallets.isEmpty) throw ExternalReceiveWalletNoDefaultWalletException();
    return wallets.first;
  }

  Future<Wallet?> _findExistingLocalWallet({
    required Environment environment,
    required ExternalReceiveWalletAccountKey key,
    required String masterFingerprint,
  }) async {
    final wallets = await _walletRepository.getWallets(
      environment: environment,
    );
    return wallets
        .where((wallet) => !wallet.isDefault)
        .where((wallet) => wallet.masterFingerprint == masterFingerprint)
        .where((wallet) => wallet.network == key.network)
        .where((wallet) => wallet.scriptType == ScriptType.bip84)
        .where((wallet) => wallet.signer == SignerEntity.local)
        .firstOrNull;
  }

  Future<void> _recordOriginOrThrow({
    required Wallet wallet,
    required ExternalReceiveWalletAccountKey key,
    required String rootFingerprint,
    String? xprvBase58,
    String? derivationPath,
    required bool repairedExistingWallet,
  }) async {
    try {
      await _recordOrigin(
        wallet: wallet,
        key: key,
        rootFingerprint: rootFingerprint,
      );
    } catch (e) {
      if (!repairedExistingWallet) {
        await _deleteDerivationBestEffort(
          xprvBase58: xprvBase58,
          derivationPath: derivationPath,
        );
        await _deleteNewWalletBestEffort(wallet);
      }
      throw ExternalReceiveWalletMetadataException(
        wallet: wallet,
        cause: e,
        repairedExistingWallet: repairedExistingWallet,
      );
    }
  }

  Future<void> _recordDerivationOrThrow({
    required Wallet wallet,
    required String xprvBase58,
    required String derivationPath,
    required String alias,
    required bool rollbackDerivationOnFailure,
    required bool repairedExistingWallet,
  }) async {
    try {
      await _bip85Repository.recordMnemonicDerivation(
        xprvBase58: xprvBase58,
        derivationPath: derivationPath,
        alias: alias,
        usage: Bip85Usage.system,
      );
    } catch (e) {
      if (rollbackDerivationOnFailure) {
        await _deleteDerivationBestEffort(
          xprvBase58: xprvBase58,
          derivationPath: derivationPath,
        );
      }
      if (!repairedExistingWallet) {
        await _deleteNewWalletBestEffort(wallet);
      }
      throw ExternalReceiveWalletMetadataException(
        wallet: wallet,
        cause: e,
        repairedExistingWallet: repairedExistingWallet,
      );
    }
  }

  Future<void> _recordOrigin({
    required Wallet wallet,
    required ExternalReceiveWalletAccountKey key,
    required String rootFingerprint,
  }) async {
    await _walletManifest.recordOrigin(
      walletId: wallet.id,
      network: walletManifestNetworkFromWalletNetwork(key.network),
      rootFingerprint: rootFingerprint,
      bip85DerivationPath: Bip85DerivationPath.mnemonic12(
        index: key.bip85Index,
      ).value,
    );
  }

  Future<void> _publishManifestBestEffort() async {
    try {
      await _walletManifest.publishLocalManifest();
    } catch (e) {
      log.warning('External receive wallet manifest publish failed', error: e);
    }
  }

  Future<void> _deleteNewWalletBestEffort(Wallet wallet) async {
    try {
      await _walletRepository.deleteWallet(walletId: wallet.id);
    } catch (e) {
      log.warning(
        'External receive wallet cleanup after origin failure failed',
        error: e,
      );
    }
  }

  Future<void> _deleteDerivationBestEffort({
    required String? xprvBase58,
    required String? derivationPath,
  }) async {
    if (xprvBase58 == null || derivationPath == null) return;
    try {
      await _bip85Repository.deleteMnemonicDerivation(
        xprvBase58: xprvBase58,
        derivationPath: derivationPath,
      );
    } catch (e) {
      log.warning(
        'External receive wallet cleanup after derivation failure failed',
        error: e,
      );
    }
  }

  Seed _seedFromMnemonic(bip39.Mnemonic mnemonic) {
    final seedBytes = Uint8List.fromList(mnemonic.seed);
    return Seed.mnemonic(
      mnemonicWords: mnemonic.words,
      bytes: seedBytes,
      masterFingerprint: bip32.Bip32Keys.fromSeed(
        seedBytes,
      ).fingerprint.toHexString(),
    );
  }
}
