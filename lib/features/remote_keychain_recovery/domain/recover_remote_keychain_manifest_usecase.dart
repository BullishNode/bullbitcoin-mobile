import 'dart:async';

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/keychain_recovery/public/keychain_recovery_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

final class RecoverRemoteKeychainManifestUsecase {
  static const defaultRecoveryBudget = Duration(seconds: 60);

  final WalletBackupFacade _walletBackup;
  final KeychainManifestFacade _manifest;
  final KeychainRecoveryFacade _recovery;
  final HealRecoveredProductsUsecase _healRecoveredProducts;
  final Clock clock;
  final Duration budget;

  const RecoverRemoteKeychainManifestUsecase(
    this._walletBackup,
    this._manifest,
    this._recovery,
    this._healRecoveredProducts, {
    this.clock = const SystemClock(),
    this.budget = defaultRecoveryBudget,
  });

  Future<RemoteKeychainRecoveryResult> execute({DateTime? deadline}) async {
    final effectiveDeadline = deadline ?? clock.nowUtc().add(budget);
    try {
      return await _executeWithin(effectiveDeadline);
    } on TimeoutException {
      return RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.timedOut,
      );
    } catch (error, stack) {
      log.warning(
        'Remote keychain recovery failed locally',
        error: error.runtimeType,
        trace: stack,
      );
      return const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.localFailure,
      );
    }
  }

  Future<RemoteKeychainRecoveryResult> _executeWithin(DateTime deadline) async {
    final fetchResult = await _walletBackup.fetchManifestImport().timeout(
      _remaining(deadline),
    );
    if (_deadlineReached(deadline)) return _timedOut;

    final WalletBackupManifestImport? manifestImport;
    switch (fetchResult) {
      case Ok(:final value):
        manifestImport = value;
      case Err(:final failure):
        return RemoteKeychainRecoveryResult(status: _statusForFailure(failure));
    }
    if (manifestImport == null) {
      return const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.noBackup,
      );
    }

    final KeychainManifestImportPlan importPlan;
    try {
      importPlan = _manifest.parseManifestFilePayload(
        manifestImport.payload,
        expectedParentFingerprint: manifestImport.parentFingerprint,
        allowEmpty: true,
      );
    } on KeychainManifestException {
      return const RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.invalid,
      );
    }
    if (importPlan.entries.isEmpty) {
      return RemoteKeychainRecoveryResult(
        status: RemoteKeychainRecoveryStatus.nothingToRestore,
        metadataPayload: manifestImport.metadataPayload,
      );
    }
    if (_deadlineReached(deadline)) return _timedOut;

    final restored = await _recovery.restoreWallets(
      importPlan,
      deadline: deadline,
    );
    final failedOutcomes = restored.walletOutcomes
        .where((outcome) => !outcome.succeeded)
        .toList(growable: false);
    final failedNostrOutcomes = restored.nostrKeyOutcomes
        .where((outcome) => !outcome.succeeded)
        .toList(growable: false);
    final createdWalletIds = restored.walletOutcomes
        .where((outcome) => outcome.succeeded && outcome.created)
        .map((outcome) => outcome.walletId)
        .toSet()
        .toList(growable: false);

    final restorationTimedOut = _deadlineReached(deadline);
    var healingTimedOut = false;
    if (!restorationTimedOut && restored.restoredCount > 0) {
      final reservations = restored.productReactivationRequiredOutcomes
          .map((outcome) => outcome.intent.reservationId)
          .toSet();
      if (reservations.isNotEmpty) {
        healingTimedOut =
            await _healRecoveredProducts.execute(
              reservations,
              deadline: deadline,
            ) ==
            RecoveredProductsHealStatus.timedOut;
      }
    }

    return RemoteKeychainRecoveryResult(
      status: restorationTimedOut || healingTimedOut
          ? RemoteKeychainRecoveryStatus.timedOut
          : _statusForRestore(restored, failedOutcomes, failedNostrOutcomes),
      restoredCount: restored.restoredCount + restored.restoredNostrKeyCount,
      failedCount: failedOutcomes.length + failedNostrOutcomes.length,
      createdWalletIds: createdWalletIds,
      metadataPayload: manifestImport.metadataPayload,
    );
  }

  RemoteKeychainRecoveryStatus _statusForFailure(WalletBackupFailure failure) {
    return switch (failure) {
      WalletBackupRemoteUnavailableFailure() =>
        RemoteKeychainRecoveryStatus.unavailable,
      WalletBackupTooLargeFailure() => RemoteKeychainRecoveryStatus.tooLarge,
      WalletBackupUnsupportedEnvelopeVersionFailure() ||
      WalletBackupUnsupportedSectionFailure() =>
        RemoteKeychainRecoveryStatus.newerVersion,
      WalletBackupHeadConflictFailure() =>
        RemoteKeychainRecoveryStatus.conflict,
      WalletBackupInvalidEnvelopeFailure() ||
      WalletBackupParentFingerprintMismatchFailure() ||
      WalletBackupEncryptionFailure() ||
      WalletBackupInvalidRemoteFailure() ||
      WalletBackupManifestFailure() => RemoteKeychainRecoveryStatus.invalid,
      WalletBackupKeyDerivationFailure() ||
      WalletBackupStorageFailure() ||
      WalletBackupSigningFailure() ||
      WalletBackupRemoteRejectedFailure() ||
      WalletBackupWalletUnavailableFailure() ||
      WalletBackupDisabledFailure() ||
      WalletBackupConfirmationRequiredFailure() ||
      WalletBackupRecoveryBlockedFailure() ||
      WalletBackupUnexpectedFailure() =>
        RemoteKeychainRecoveryStatus.localFailure,
    };
  }

  RemoteKeychainRecoveryStatus _statusForRestore(
    KeychainRecoveryResult result,
    List<KeychainRecoveryWalletRestoreOutcome> failedOutcomes,
    List<KeychainRecoveryNostrKeyRestoreOutcome> failedNostrOutcomes,
  ) {
    if (failedOutcomes.isEmpty && failedNostrOutcomes.isEmpty) {
      return RemoteKeychainRecoveryStatus.restored;
    }
    if (failedOutcomes.any(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryWalletRestoreStatus.skippedTimeBudgetExpired,
        ) ||
        failedNostrOutcomes.any(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryNostrKeyRestoreStatus.skippedTimeBudgetExpired,
        )) {
      return RemoteKeychainRecoveryStatus.timedOut;
    }
    if (result.restoredCount + result.restoredNostrKeyCount > 0) {
      return RemoteKeychainRecoveryStatus.partiallyRestored;
    }
    final allInvalid =
        failedOutcomes.every(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryWalletRestoreStatus.failedInvalidImportPlan,
        ) &&
        failedNostrOutcomes.every(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryNostrKeyRestoreStatus.failedInvalidImportPlan,
        );
    if (allInvalid) {
      return RemoteKeychainRecoveryStatus.invalid;
    }
    if (failedNostrOutcomes.isEmpty &&
        failedOutcomes.every(
          (outcome) =>
              outcome.status ==
              KeychainRecoveryWalletRestoreStatus.failedConflict,
        )) {
      return RemoteKeychainRecoveryStatus.conflict;
    }
    return RemoteKeychainRecoveryStatus.localFailure;
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(clock.nowUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _deadlineReached(DateTime deadline) {
    return !clock.nowUtc().isBefore(deadline);
  }

  static const _timedOut = RemoteKeychainRecoveryResult(
    status: RemoteKeychainRecoveryStatus.timedOut,
  );
}
