// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_wallet_behavior_defaults_usecase.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_result.dart';
import 'package:bb_mobile/features/keychain_recovery/domain/keychain_recovery_wallet_materializer_port.dart';

class RestoreKeychainManifestWalletsUsecase {
  final KeychainRecoveryWalletMaterializerPort _walletMaterializer;
  final KeychainManifestFacade _keychainManifest;
  final ApplyWalletBehaviorDefaultsUsecase _applyWalletBehaviorDefaults;
  final Bip85RegistryFacade _registry;
  final KeychainManifestBackupWalletPort? _backupWallet;

  const RestoreKeychainManifestWalletsUsecase({
    required KeychainRecoveryWalletMaterializerPort walletMaterializer,
    required KeychainManifestFacade keychainManifest,
    required ApplyWalletBehaviorDefaultsUsecase applyWalletBehaviorDefaults,
    required Bip85RegistryFacade bip85Registry,
    KeychainManifestBackupWalletPort? backupWallet,
  }) : _walletMaterializer = walletMaterializer,
       _keychainManifest = keychainManifest,
       _applyWalletBehaviorDefaults = applyWalletBehaviorDefaults,
       _registry = bip85Registry,
       _backupWallet = backupWallet;

  Future<KeychainRecoveryResult> execute(
    KeychainManifestImportPlan importPlan, {
    DateTime? deadline,
  }) async {
    final outcomes = <KeychainRecoveryWalletRestoreOutcome>[];
    final entryIds = <String>{};
    final walletIds = <String>{};
    for (final entry in importPlan.entries) {
      // Cooperative time-budget check: once the deadline has passed we stop
      // BEFORE materializing any further wallet, so a recovery that outlives its
      // budget can never keep creating wallets in the background. Validation
      // still runs so already-validated identity constraints are preserved, but
      // nothing new is derived.
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        outcomes.addAll(_skippedForTimeBudget(entry.walletMaterializations));
        continue;
      }
      final validationFailure = _validateEntry(
        importPlan: importPlan,
        entry: entry,
        entryIds: entryIds,
        walletIds: walletIds,
      );
      if (validationFailure != null) {
        outcomes.addAll(validationFailure);
        continue;
      }
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
    final nostrOutcomes = await _restoreNostrKeys(
      importPlan,
      deadline: deadline,
    );
    return KeychainRecoveryResult(
      walletOutcomes: outcomes,
      nostrKeyOutcomes: nostrOutcomes,
    );
  }

  Future<List<KeychainRecoveryNostrKeyRestoreOutcome>> _restoreNostrKeys(
    KeychainManifestImportPlan importPlan, {
    DateTime? deadline,
  }) async {
    final intents = importPlan.nostrKeyMaterializations;
    if (intents.isEmpty) return const [];
    final wallet = _backupWallet;
    if (wallet == null) {
      return intents
          .map(
            (intent) => _nostrOutcome(
              intent,
              KeychainRecoveryNostrKeyRestoreStatus.failedVerification,
            ),
          )
          .toList(growable: false);
    }
    final source = await wallet.deriveDefaultWallet();
    final existing = await _keychainManifest.getNostrKeys(
      importPlan.parentFingerprint,
    );
    final outcomes = <KeychainRecoveryNostrKeyRestoreOutcome>[];
    final seenEntryIds = <String>{};
    for (final intent in intents) {
      if (deadline != null && !DateTime.now().isBefore(deadline)) {
        outcomes.add(
          _nostrOutcome(
            intent,
            KeychainRecoveryNostrKeyRestoreStatus.skippedTimeBudgetExpired,
          ),
        );
        continue;
      }
      if (!_validNostrIntent(importPlan, intent, seenEntryIds) ||
          source.parentFingerprint.toLowerCase() !=
              importPlan.parentFingerprint.toLowerCase()) {
        outcomes.add(
          _nostrOutcome(
            intent,
            KeychainRecoveryNostrKeyRestoreStatus.failedInvalidImportPlan,
          ),
        );
        continue;
      }
      final handle = NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: source.xprvBase58,
        hardenedPath: intent.bip85DerivationPath,
      );
      if (handle.publicKeyHex != intent.publicKeyHex) {
        outcomes.add(
          _nostrOutcome(
            intent,
            KeychainRecoveryNostrKeyRestoreStatus.failedVerification,
          ),
        );
        continue;
      }
      final existingRecord = existing.where(
        (record) => record.entryId == intent.entryId,
      );
      var alreadyPresent = false;
      if (existingRecord.isNotEmpty) {
        final stored = existingRecord.single.nostrKeyMaterialization;
        if (stored.publicKeyHex != intent.publicKeyHex ||
            stored.keyKind != intent.keyKind) {
          outcomes.add(
            _nostrOutcome(
              intent,
              KeychainRecoveryNostrKeyRestoreStatus.failedVerification,
            ),
          );
          continue;
        }
        alreadyPresent = true;
      }
      try {
        await _keychainManifest.recordRecoveredNostrKey(
          KeychainManifestNostrKeyRequest(
            reservationId: intent.reservationId,
            parentFingerprint: importPlan.parentFingerprint,
            derivationPath: intent.bip85DerivationPath,
            publicKeyHex: intent.publicKeyHex,
            keyKind: intent.keyKind,
            purpose: intent.purpose,
            description: intent.description,
          ),
          now: DateTime.fromMillisecondsSinceEpoch(
            intent.createdAt * 1000,
            isUtc: true,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            intent.updatedAt * 1000,
            isUtc: true,
          ),
        );
        outcomes.add(
          _nostrOutcome(
            intent,
            alreadyPresent
                ? KeychainRecoveryNostrKeyRestoreStatus.alreadyPresent
                : KeychainRecoveryNostrKeyRestoreStatus.created,
          ),
        );
      } on KeychainManifestException {
        outcomes.add(
          _nostrOutcome(
            intent,
            KeychainRecoveryNostrKeyRestoreStatus.failedManifestRecord,
          ),
        );
      }
    }
    return outcomes;
  }

  bool _validNostrIntent(
    KeychainManifestImportPlan importPlan,
    KeychainManifestNostrKeyMaterializationIntent intent,
    Set<String> seenEntryIds,
  ) {
    if (!seenEntryIds.add(intent.entryId) ||
        intent.entryId !=
            _entryId(
              importPlan.parentFingerprint,
              intent.bip85DerivationPath,
            )) {
      return false;
    }
    final isDynamic =
        intent.reservationId == _registry.nostrUserKeyReservationId;
    final reservation = _registry.reservationById(intent.reservationId);
    return isDynamic
        ? intent.keyKind == KeychainManifestNostrKeyKind.userGenerated &&
              _registry.isNostrUserKeyPath(intent.bip85DerivationPath)
        : intent.keyKind == KeychainManifestNostrKeyKind.reserved &&
              reservation is Bip85KeyReservation &&
              reservation.scope.matchesExactPath(intent.bip85DerivationPath) &&
              reservation.application.number ==
                  _registry.nostrApplicationNumber;
  }

  KeychainRecoveryNostrKeyRestoreOutcome _nostrOutcome(
    KeychainManifestNostrKeyMaterializationIntent intent,
    KeychainRecoveryNostrKeyRestoreStatus status,
  ) => KeychainRecoveryNostrKeyRestoreOutcome(
    intent: KeychainRecoveryNostrKeyIntent(
      entryId: intent.entryId,
      reservationId: intent.reservationId,
      bip85DerivationPath: intent.bip85DerivationPath,
      publicKeyHex: intent.publicKeyHex,
      keyKind: intent.keyKind,
      purpose: intent.purpose,
    ),
    status: status,
  );

  List<KeychainRecoveryWalletRestoreOutcome>? _validateEntry({
    required KeychainManifestImportPlan importPlan,
    required KeychainManifestImportEntryIntent entry,
    required Set<String> entryIds,
    required Set<String> walletIds,
  }) {
    final reservation = _registry.reservationById(entry.reservationId);
    // V1 recovery is limited to wallet-seed reservations, so the shape check
    // (which also covers an unknown reservation) proves the typed wallet
    // index before it is compared against the file-claimed one.
    if (reservation is! Bip85WalletSeedReservation ||
        entryIds.contains(entry.entryId) ||
        entry.parentFingerprint != importPlan.parentFingerprint ||
        entry.entryId !=
            _entryId(importPlan.parentFingerprint, entry.bip85DerivationPath) ||
        !reservation.scope.matchesExactPath(entry.bip85DerivationPath) ||
        !_supportsWalletManifestRecovery(reservation) ||
        reservation.owner.name != entry.ownerFeature ||
        reservation.purpose.name != entry.entryType ||
        reservation.application.number != entry.bip85Application ||
        reservation.walletIndex != entry.bip85Index) {
      return _failedInvalidImportPlan(entry.walletMaterializations);
    }

    final walletKeys = <String>{};
    for (final intent in entry.walletMaterializations) {
      if (intent.entryId != entry.entryId ||
          intent.reservationId != entry.reservationId ||
          intent.bip85DerivationPath != entry.bip85DerivationPath ||
          !walletKeys.add(
            _materializationKey(
              entryId: intent.entryId,
              walletId: intent.walletId,
            ),
          ) ||
          walletIds.contains(intent.walletId)) {
        return _failedInvalidImportPlan(entry.walletMaterializations);
      }
    }
    entryIds.add(entry.entryId);
    walletIds.addAll(
      entry.walletMaterializations.map((intent) => intent.walletId),
    );
    return null;
  }

  bool _supportsWalletManifestRecovery(Bip85Reservation reservation) {
    // Recovery remains limited to reservations explicitly classified as
    // locally materializable. Product/server healing is owned by the remote
    // recovery orchestrator after this local operation succeeds.
    return KeychainManifestReservationSupport.supportsV1Recovery(reservation);
  }

  KeychainRecoveryWalletMaterializationBatch _materializationBatch({
    required KeychainManifestImportPlan importPlan,
    required KeychainManifestImportEntryIntent entry,
  }) {
    // _validateEntry already proved the reservation resolves to the
    // wallet-seed shape for every entry that reaches materialization.
    final reservation =
        _registry.reservationById(entry.reservationId)!
            as Bip85WalletSeedReservation;
    return KeychainRecoveryWalletMaterializationBatch(
      parentFingerprint: importPlan.parentFingerprint,
      reservationId: entry.reservationId,
      bip85Index: reservation.walletIndex,
      deterministicAlias: reservation.deterministicAlias,
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
      scriptType: intent.scriptType,
    );
  }

  List<KeychainRecoveryWalletRestoreOutcome> _failedInvalidImportPlan(
    List<KeychainManifestWalletMaterializationIntent> intents,
  ) {
    return intents
        .map(
          (intent) => KeychainRecoveryWalletRestoreOutcome(
            intent: _walletIntent(intent),
            status: KeychainRecoveryWalletRestoreStatus.failedInvalidImportPlan,
            materializedWalletId: intent.walletId,
          ),
        )
        .toList(growable: false);
  }

  List<KeychainRecoveryWalletRestoreOutcome> _skippedForTimeBudget(
    List<KeychainManifestWalletMaterializationIntent> intents,
  ) {
    return intents
        .map(
          (intent) => KeychainRecoveryWalletRestoreOutcome(
            intent: _walletIntent(intent),
            status:
                KeychainRecoveryWalletRestoreStatus.skippedTimeBudgetExpired,
            materializedWalletId: intent.walletId,
          ),
        )
        .toList(growable: false);
  }

  String _entryId(String parentFingerprint, String bip85DerivationPath) {
    return '$parentFingerprint:$bip85DerivationPath';
  }

  String _materializationKey({
    required String entryId,
    required String walletId,
  }) {
    return '$entryId:$walletId';
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
                materializedWalletId: intent.walletId,
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
    final derivationPath = materializationResult.derivationPath;
    if (wallets.isEmpty || derivationPath == null) return [];
    try {
      await _keychainManifest.recordRecoveredDerivation(
        KeychainManifestReservedDerivationRequest(
          reservationId: reservationId,
          parentFingerprint: parentFingerprint,
          derivationPath: derivationPath,
          materializations: wallets
              .map(
                (wallet) => KeychainManifestWalletMaterializationRequest(
                  walletId: wallet.walletId,
                  childSeedFingerprint: wallet.childSeedFingerprint,
                  network: wallet.network,
                  scriptType: wallet.scriptType,
                ),
              )
              .toList(growable: false),
        ),
      );
      // Re-apply the locked Get Paid posture (decision [1]/[C]/KC-6) using the
      // materialized wallet's verified network. Post-commitment per AD-3: the
      // manifest record above is the commitment point, so a defaults failure is
      // logged and never fails the restore.
      await _applyGetPaidPostureBestEffort(wallets);
      return wallets
          .map((wallet) {
            return KeychainRecoveryWalletRestoreOutcome(
              intent: wallet.intent,
              status: _successStatus(wallet),
              materializedWalletId: wallet.walletId,
              created: wallet.created,
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
              materializedWalletId: wallet.walletId,
            );
          })
          .toList(growable: false);
    }
  }

  Future<void> _applyGetPaidPostureBestEffort(
    List<KeychainRecoveryMaterializedWallet> wallets,
  ) async {
    for (final wallet in wallets) {
      try {
        await _applyWalletBehaviorDefaults.execute(
          walletId: wallet.intent.walletId,
          hideOnHome: wallet.network.isLiquid,
          autoSweepEnabled: wallet.network.isLiquid,
        );
      } catch (e, stack) {
        // Log the fingerprint/id, never the material; the restore still
        // succeeds (post-commitment best effort, AD-3).
        log.warning(
          'Get Paid posture defaults failed for restored wallet '
          '${wallet.intent.walletId}',
          error: e,
          trace: stack,
        );
      }
    }
  }

  KeychainRecoveryWalletRestoreStatus _successStatus(
    KeychainRecoveryMaterializedWallet wallet,
  ) {
    if (wallet.created) {
      return _successfulRestoreStatus(
        intent: wallet.intent,
        defaultStatus: KeychainRecoveryWalletRestoreStatus.created,
      );
    }
    return _successfulRestoreStatus(
      intent: wallet.intent,
      defaultStatus: KeychainRecoveryWalletRestoreStatus.alreadyPresent,
    );
  }

  KeychainRecoveryWalletRestoreStatus _successfulRestoreStatus({
    required KeychainRecoveryWalletIntent intent,
    required KeychainRecoveryWalletRestoreStatus defaultStatus,
  }) {
    if (_requiresProductReactivation(intent.reservationId)) {
      return KeychainRecoveryWalletRestoreStatus.requiresProductReactivation;
    }
    return defaultStatus;
  }

  bool _requiresProductReactivation(String reservationId) {
    final reservation = _registry.reservationById(reservationId);
    if (reservation == null) return false;
    return KeychainManifestReservationSupport.requiresProductReactivationOnRecovery(
      reservation,
    );
  }
}
