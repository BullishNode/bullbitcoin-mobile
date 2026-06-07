import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/application/ports/keychain_recovery_wallet_materializer_port.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';

class RestoreKeychainManifestWalletsUsecase {
  final KeychainRecoveryWalletMaterializerPort _walletMaterializer;
  final KeychainManifestFacade _keychainManifest;
  final Bip85RegistryFacade _registry;

  const RestoreKeychainManifestWalletsUsecase({
    required KeychainRecoveryWalletMaterializerPort walletMaterializer,
    required KeychainManifestFacade keychainManifest,
    Bip85RegistryFacade registry = const Bip85RegistryFacade(),
  }) : _walletMaterializer = walletMaterializer,
       _keychainManifest = keychainManifest,
       _registry = registry;

  Future<KeychainRecoveryResult> execute(
    KeychainManifestImportPlan importPlan,
  ) async {
    final outcomes = <KeychainRecoveryWalletRestoreOutcome>[];
    for (final entry in importPlan.entries) {
      final batch = _materializationBatch(importPlan: importPlan, entry: entry);
      final materializationResult = await _materialize(batch);
      outcomes.addAll(materializationResult.failedOutcomes);
      outcomes.addAll(
        await _recordMaterializedWallets(
          parentFingerprint: importPlan.parentFingerprint,
          reservationId: entry.reservationId,
          materializationResult: materializationResult,
        ),
      );
    }
    return KeychainRecoveryResult(walletOutcomes: outcomes);
  }

  KeychainRecoveryWalletMaterializationBatch _materializationBatch({
    required KeychainManifestImportPlan importPlan,
    required KeychainManifestImportEntryIntent entry,
  }) {
    final reservation = _registry.reservationById(entry.reservationId);
    return KeychainRecoveryWalletMaterializationBatch(
      parentFingerprint: importPlan.parentFingerprint,
      reservationId: entry.reservationId,
      bip85Index: entry.bip85Index,
      deterministicAlias:
          reservation?.deterministicAlias ?? entry.reservationId,
      intents: entry.walletMaterializations
          .map(_walletIntent)
          .toList(growable: false),
    );
  }

  KeychainRecoveryWalletIntent _walletIntent(
    KeychainManifestWalletMaterializationIntent intent,
  ) {
    return KeychainRecoveryWalletIntent(
      entryId: intent.entryId,
      reservationId: intent.reservationId,
      bip85DerivationPath: intent.bip85DerivationPath,
      walletId: intent.walletId,
      childSeedFingerprint: intent.childSeedFingerprint,
      network: intent.network,
      walletPurpose: intent.walletPurpose,
      scriptType: intent.scriptType,
    );
  }

  Future<KeychainRecoveryWalletMaterializationResult> _materialize(
    KeychainRecoveryWalletMaterializationBatch batch,
  ) async {
    try {
      return await _walletMaterializer.materialize(batch);
    } catch (_) {
      return KeychainRecoveryWalletMaterializationResult(
        materializedWallets: const [],
        failedOutcomes: batch.intents
            .map(
              (intent) => KeychainRecoveryWalletRestoreOutcome(
                intent: intent,
                status:
                    KeychainRecoveryWalletRestoreStatus.failedWalletCreation,
                walletId: intent.walletId,
              ),
            )
            .toList(growable: false),
      );
    }
  }

  Future<List<KeychainRecoveryWalletRestoreOutcome>>
  _recordMaterializedWallets({
    required String parentFingerprint,
    required String reservationId,
    required KeychainRecoveryWalletMaterializationResult materializationResult,
  }) async {
    final wallets = materializationResult.materializedWallets;
    if (wallets.isEmpty) return [];
    try {
      final recordResult = await _keychainManifest.recordReservedDerivation(
        KeychainManifestReservedDerivationRequest(
          reservationId: reservationId,
          parentFingerprint: parentFingerprint,
          materializations: wallets
              .map(
                (wallet) => KeychainManifestWalletMaterializationRequest(
                  walletId: wallet.wallet.id,
                  childSeedFingerprint: wallet.childSeedFingerprint,
                  network: wallet.wallet.network,
                  walletPurpose: wallet.intent.walletPurpose,
                  scriptType: wallet.wallet.scriptType,
                ),
              )
              .toList(growable: false),
        ),
      );
      final insertedWalletIds = recordResult.insertedMaterializations
          .where(
            (materialization) =>
                materialization.materializationType ==
                KeychainManifestRecordedMaterialization.walletType,
          )
          .map((materialization) => materialization.materializationId)
          .toSet();
      return wallets
          .map((wallet) {
            return KeychainRecoveryWalletRestoreOutcome(
              intent: wallet.intent,
              status: _successStatus(wallet, insertedWalletIds),
              walletId: wallet.wallet.id,
            );
          })
          .toList(growable: false);
    } on KeychainManifestException {
      final rollback = materializationResult.rollbackCreatedWallets;
      if (rollback != null) {
        try {
          await rollback();
        } catch (_) {
          // Preserve the recovery failure result; rollback is best effort here.
        }
      }
      return wallets
          .map((wallet) {
            return KeychainRecoveryWalletRestoreOutcome(
              intent: wallet.intent,
              status: KeychainRecoveryWalletRestoreStatus.failedManifestRecord,
              walletId: wallet.wallet.id,
            );
          })
          .toList(growable: false);
    }
  }

  KeychainRecoveryWalletRestoreStatus _successStatus(
    KeychainRecoveryMaterializedWallet wallet,
    Set<String> insertedWalletIds,
  ) {
    if (wallet.created) return KeychainRecoveryWalletRestoreStatus.created;
    if (insertedWalletIds.contains(wallet.wallet.id)) {
      return KeychainRecoveryWalletRestoreStatus.metadataRepaired;
    }
    return KeychainRecoveryWalletRestoreStatus.alreadyPresent;
  }
}
