import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_wallet_operations_port.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network_mapper.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_restore_result.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_wallet_type.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;

class RestoreWalletManifestSnapshotUsecase {
  final WalletManifestWalletOperationsPort _walletOperations;
  final FetchWalletManifestOriginsUsecase _fetchOrigins;
  final RecordWalletManifestOriginUsecase _recordOrigin;
  final DeriveWalletManifestRootKeyUsecase _deriveRootKey;

  RestoreWalletManifestSnapshotUsecase({
    required WalletManifestWalletOperationsPort walletOperations,
    required FetchWalletManifestOriginsUsecase fetchOrigins,
    required RecordWalletManifestOriginUsecase recordOrigin,
    required DeriveWalletManifestRootKeyUsecase deriveRootKey,
  }) : _walletOperations = walletOperations,
       _fetchOrigins = fetchOrigins,
       _recordOrigin = recordOrigin,
       _deriveRootKey = deriveRootKey;

  Future<WalletManifestSnapshotRestoreResult> execute({
    required WalletManifestSnapshot snapshot,
  }) async {
    final rootKey = await _safeDeriveRootKey();
    final existingOrigins = {
      for (final origin in await _fetchOrigins.execute())
        origin.identity: origin,
    };
    final existingWallets = await _walletOperations.getWallets(sync: false);
    final existingWalletsById = {
      for (final wallet in existingWallets) wallet.id: wallet,
    };
    final usedLabels = existingWallets
        .map((wallet) => wallet.label?.trim())
        .whereType<String>()
        .where((label) => label.isNotEmpty)
        .toSet();
    final outcomes = <WalletManifestAccountRestoreOutcome>[];

    for (final account in snapshot.collapseDuplicates().accounts) {
      if (account.rootFingerprint != rootKey.rootFingerprint) {
        outcomes.add(
          WalletManifestAccountRestoreOutcome(
            account: account,
            status: WalletManifestRestoreStatus.skippedWrongRoot,
          ),
        );
        continue;
      }

      final existingOrigin = existingOrigins[account.identity];
      if (existingOrigin != null) {
        final existingOriginWallet =
            existingWalletsById[existingOrigin.walletId];
        if (existingOriginWallet != null) {
          outcomes.add(
            WalletManifestAccountRestoreOutcome(
              account: account,
              status: WalletManifestRestoreStatus.alreadyPresent,
              walletId: existingOriginWallet.id,
              actualLabel: existingOriginWallet.label,
            ),
          );
          continue;
        }
      }

      try {
        final outcome = await _restoreAccount(
          xprvBase58: rootKey.xprvBase58,
          account: account,
          existingWallets: existingWallets,
          usedLabels: usedLabels,
        );
        usedLabels.add(outcome.label);
        await _runStage(
          stage: WalletManifestRestoreFailureStage.recordOrigin,
          walletId: outcome.wallet.id,
          actualLabel: outcome.label,
          action: () async {
            try {
              await _recordOrigin.execute(
                walletId: outcome.wallet.id,
                network: account.network,
                rootFingerprint: account.rootFingerprint,
                bip85DerivationPath: account.bip85DerivationPath.value,
              );
            } catch (_) {
              if (outcome.created) {
                await _rollbackCreatedWallet(
                  xprvBase58: rootKey.xprvBase58,
                  walletId: outcome.wallet.id,
                  derivationPath: outcome.derivationPath,
                );
              }
              rethrow;
            }
          },
        );
        if (outcome.created) {
          existingWalletsById[outcome.wallet.id] = outcome.wallet;
          outcomes.add(
            WalletManifestAccountRestoreOutcome(
              account: account,
              status: WalletManifestRestoreStatus.created,
              walletId: outcome.wallet.id,
              actualLabel: outcome.label,
            ),
          );
        } else {
          outcomes.add(
            WalletManifestAccountRestoreOutcome(
              account: account,
              status: WalletManifestRestoreStatus.alreadyPresent,
              walletId: outcome.wallet.id,
              actualLabel: outcome.wallet.label ?? outcome.label,
              walletStateChanged: true,
            ),
          );
        }
      } on _WalletManifestRestoreStageException catch (e) {
        outcomes.add(
          WalletManifestAccountRestoreOutcome(
            account: account,
            status: WalletManifestRestoreStatus.failed,
            walletId: e.walletId,
            actualLabel: e.actualLabel,
            failureStage: e.stage,
            cause: e.cause,
          ),
        );
      } catch (e) {
        outcomes.add(
          WalletManifestAccountRestoreOutcome(
            account: account,
            status: WalletManifestRestoreStatus.failed,
            failureStage: WalletManifestRestoreFailureStage.createWallet,
            cause: e,
          ),
        );
      }
    }

    return WalletManifestSnapshotRestoreResult(outcomes: outcomes);
  }

  Future<WalletManifestRootKeyContext> _safeDeriveRootKey() async {
    try {
      return await _deriveRootKey.execute();
    } on WalletManifestSnapshotRestoreException {
      rethrow;
    } catch (e) {
      throw WalletManifestSnapshotRestoreException(e);
    }
  }

  Future<_WalletManifestRestoreOutcome> _restoreAccount({
    required String xprvBase58,
    required WalletManifestAccount account,
    required List<Wallet> existingWallets,
    required Set<String> usedLabels,
  }) async {
    final label = _walletLabel(account, usedLabels: usedLabels);
    final usage = account.walletType == WalletManifestWalletType.manual
        ? Bip85Usage.manual
        : Bip85Usage.system;
    final bip85 = await _runStage(
      stage: WalletManifestRestoreFailureStage.deriveMnemonic,
      action: () => _walletOperations.deriveMnemonicPreview(
        xprvBase58: xprvBase58,
        length: bip39.MnemonicLength.words12,
        index: account.bip85Index,
      ),
    );
    final seed = await _runStage(
      stage: WalletManifestRestoreFailureStage.createSeed,
      action: () => _walletOperations.createSeedFromMnemonic(
        mnemonicWords: bip85.mnemonic.words,
      ),
    );
    final network = walletNetworkFromWalletManifestNetwork(account.network);
    final existing = _findExistingWallet(
      existingWallets: existingWallets,
      network: network,
      masterFingerprint: seed.masterFingerprint,
    );
    if (existing != null) {
      await _recordBip85Derivation(
        xprvBase58: xprvBase58,
        derivationPath: bip85.derivation,
        label: existing.label ?? label,
        usage: usage,
        walletId: existing.id,
      );
      return _WalletManifestRestoreOutcome(
        wallet: existing,
        label: label,
        created: false,
        derivationPath: bip85.derivation,
      );
    }

    final wallet = await _runStage(
      stage: WalletManifestRestoreFailureStage.createWallet,
      action: () => _walletOperations.createWallet(
        seed: seed,
        network: network,
        scriptType: ScriptType.bip84,
        label: label,
        sync: false,
      ),
    );
    try {
      await _recordBip85Derivation(
        xprvBase58: xprvBase58,
        derivationPath: bip85.derivation,
        label: label,
        usage: usage,
        walletId: wallet.id,
        actualLabel: label,
      );
    } catch (_) {
      await _rollbackCreatedWallet(
        xprvBase58: xprvBase58,
        walletId: wallet.id,
        derivationPath: bip85.derivation,
      );
      rethrow;
    }
    return _WalletManifestRestoreOutcome(
      wallet: wallet,
      label: label,
      created: true,
      derivationPath: bip85.derivation,
    );
  }

  Future<void> _rollbackCreatedWallet({
    required String xprvBase58,
    required String walletId,
    required String derivationPath,
  }) async {
    try {
      await _walletOperations.deleteWallet(walletId: walletId);
    } catch (_) {}
    try {
      await _walletOperations.deleteMnemonicDerivation(
        xprvBase58: xprvBase58,
        derivationPath: derivationPath,
      );
    } catch (_) {}
  }

  Wallet? _findExistingWallet({
    required List<Wallet> existingWallets,
    required Network network,
    required String masterFingerprint,
  }) {
    for (final wallet in existingWallets) {
      if (wallet.network == network &&
          wallet.masterFingerprint == masterFingerprint &&
          wallet.scriptType == ScriptType.bip84 &&
          wallet.signer == SignerEntity.local &&
          !wallet.isDefault) {
        return wallet;
      }
    }
    return null;
  }

  Future<void> _recordBip85Derivation({
    required String xprvBase58,
    required String derivationPath,
    required String label,
    required Bip85Usage usage,
    required String walletId,
    String? actualLabel,
  }) {
    return _runStage(
      stage: WalletManifestRestoreFailureStage.recordBip85,
      walletId: walletId,
      actualLabel: actualLabel ?? label,
      action: () => _walletOperations.recordMnemonicDerivation(
        xprvBase58: xprvBase58,
        derivationPath: derivationPath,
        alias: label,
        usage: usage,
      ),
    );
  }

  Future<T> _runStage<T>({
    required WalletManifestRestoreFailureStage stage,
    required Future<T> Function() action,
    String? walletId,
    String? actualLabel,
  }) async {
    try {
      return await action();
    } catch (e) {
      throw _WalletManifestRestoreStageException(
        stage: stage,
        cause: e,
        walletId: walletId,
        actualLabel: actualLabel,
      );
    }
  }

  String _walletLabel(
    WalletManifestAccount account, {
    required Set<String> usedLabels,
  }) {
    final name = account.name?.trim();
    final base = name != null && name.isNotEmpty
        ? name
        : account.fallbackName(includeNetworkSuffix: true);
    if (!usedLabels.contains(base)) return base;

    var suffix = 2;
    while (usedLabels.contains('$base $suffix')) {
      suffix += 1;
    }
    return '$base $suffix';
  }
}

class _WalletManifestRestoreStageException implements Exception {
  final WalletManifestRestoreFailureStage stage;
  final Object cause;
  final String? walletId;
  final String? actualLabel;

  _WalletManifestRestoreStageException({
    required this.stage,
    required this.cause,
    this.walletId,
    this.actualLabel,
  });
}

class _WalletManifestRestoreOutcome {
  final Wallet wallet;
  final String label;
  final bool created;
  final String derivationPath;

  _WalletManifestRestoreOutcome({
    required this.wallet,
    required this.label,
    required this.created,
    required this.derivationPath,
  });
}
