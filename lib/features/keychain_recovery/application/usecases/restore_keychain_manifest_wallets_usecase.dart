import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/application/ports/keychain_recovery_wallet_materializer_port.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';

class RestoreKeychainManifestWalletsUsecase {
  final KeychainRecoveryWalletMaterializerPort _walletMaterializer;
  final KeychainManifestFacade _keychainManifest;

  const RestoreKeychainManifestWalletsUsecase({
    required KeychainRecoveryWalletMaterializerPort walletMaterializer,
    required KeychainManifestFacade keychainManifest,
  }) : _walletMaterializer = walletMaterializer,
       _keychainManifest = keychainManifest;

  Future<KeychainRecoveryResult> execute(
    KeychainManifestImportPlan importPlan,
  ) async {
    final outcomes = <KeychainRecoveryWalletRestoreOutcome>[];
    for (final entry in importPlan.entries) {
      final materializationResult = await _walletMaterializer.materialize(
        KeychainRecoveryWalletMaterializationBatch(
          parentFingerprint: importPlan.parentFingerprint,
          reservationId: entry.reservationId,
          bip85DerivationPath: entry.bip85DerivationPath,
          bip85Index: entry.bip85Index,
          intents: entry.walletMaterializations,
        ),
      );
      outcomes.addAll(materializationResult.failedOutcomes);
      outcomes.addAll(
        await _recordMaterializedWallets(
          parentFingerprint: importPlan.parentFingerprint,
          reservationId: entry.reservationId,
          wallets: materializationResult.materializedWallets,
        ),
      );
    }
    return KeychainRecoveryResult(walletOutcomes: outcomes);
  }

  Future<List<KeychainRecoveryWalletRestoreOutcome>>
  _recordMaterializedWallets({
    required String parentFingerprint,
    required String reservationId,
    required List<KeychainRecoveryMaterializedWallet> wallets,
  }) async {
    if (wallets.isEmpty) return [];
    try {
      await _keychainManifest.recordReservedDerivation(
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
      return wallets
          .map((wallet) {
            return KeychainRecoveryWalletRestoreOutcome(
              intent: wallet.intent,
              status: wallet.created
                  ? KeychainRecoveryWalletRestoreStatus.created
                  : KeychainRecoveryWalletRestoreStatus.alreadyPresent,
              walletId: wallet.wallet.id,
            );
          })
          .toList(growable: false);
    } on KeychainManifestException {
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
}
