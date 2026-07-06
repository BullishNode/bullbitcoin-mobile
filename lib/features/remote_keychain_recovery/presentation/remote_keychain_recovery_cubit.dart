// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/recovered_products_heal_outcome.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/load_automated_backup_consent_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/publish_restored_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RemoteKeychainRecoveryCubit extends Cubit<RemoteKeychainRecoveryState> {
  final CheckRemoteKeychainRecoveryUsecase _checkRecovery;
  final RestoreRemoteKeychainManifestUsecase _restoreManifest;
  final LoadAutomatedBackupConsentUsecase _loadConsent;
  final HealRecoveredProductsUsecase _healRecoveredProducts;
  final PublishRestoredKeychainBackupUsecase _publishRestoredBackup;

  KeychainManifestImportPlan? _pendingOlderImportPlan;
  int? _pendingOlderNewestEventCreatedAt;
  int? _pendingOlderSelectedEventCreatedAt;
  int _operationId = 0;

  RemoteKeychainRecoveryCubit({
    required CheckRemoteKeychainRecoveryUsecase checkRecovery,
    required RestoreRemoteKeychainManifestUsecase restoreManifest,
    required LoadAutomatedBackupConsentUsecase loadConsent,
    required HealRecoveredProductsUsecase healRecoveredProducts,
    required PublishRestoredKeychainBackupUsecase publishRestoredBackup,
  }) : _checkRecovery = checkRecovery,
       _restoreManifest = restoreManifest,
       _loadConsent = loadConsent,
       _healRecoveredProducts = healRecoveredProducts,
       _publishRestoredBackup = publishRestoredBackup,
       super(const RemoteKeychainRecoveryState());

  Future<void> start({bool acceptedThirdPartyRelayDisclosure = false}) async {
    final operationId = ++_operationId;
    _clearPendingOlder();
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.checking,
      ),
    );
    try {
      // The persisted disclosure ack short-circuits the relay-disclosure gate:
      // it is the SAME preference the creation-time consent writes (R2-P21c).
      // An explicit true from acceptRelayDisclosure() still works.
      final effectiveDisclosure =
          acceptedThirdPartyRelayDisclosure || await _loadConsent.execute();
      if (!_isActive(operationId)) return;
      final result = await _checkRecovery.execute(
        acceptedThirdPartyRelayDisclosure: effectiveDisclosure,
      );
      if (!_isActive(operationId)) return;
      switch (result.status) {
        case RemoteKeychainRecoveryCheckStatus.requiresRelayDisclosure:
          emit(
            const RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.requiresRelayDisclosure,
            ),
          );
        case RemoteKeychainRecoveryCheckStatus.latestManifestReady:
          final importPlan = result.importPlan;
          if (importPlan == null) {
            emit(
              const RemoteKeychainRecoveryState(
                status: RemoteKeychainRecoveryStatus.noRecoverableManifest,
              ),
            );
            return;
          }
          await _restore(
            importPlan,
            operationId,
            newestEventCreatedAt: result.newestEventCreatedAt,
            selectedEventCreatedAt: result.selectedEventCreatedAt,
            isOlderRestore: false,
          );
        case RemoteKeychainRecoveryCheckStatus.olderManifestAvailable:
          _pendingOlderImportPlan = result.importPlan;
          _pendingOlderNewestEventCreatedAt = result.newestEventCreatedAt;
          _pendingOlderSelectedEventCreatedAt = result.selectedEventCreatedAt;
          emit(
            RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.olderManifestAvailable,
              newestEventCreatedAt: result.newestEventCreatedAt,
              selectedEventCreatedAt: result.selectedEventCreatedAt,
            ),
          );
        case RemoteKeychainRecoveryCheckStatus.noManifestFound:
          emit(
            const RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.noManifestFound,
            ),
          );
        case RemoteKeychainRecoveryCheckStatus.relaysUnavailable:
          emit(
            const RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.relaysUnavailable,
            ),
          );
        case RemoteKeychainRecoveryCheckStatus.noRecoverableManifest:
          emit(
            const RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.noRecoverableManifest,
            ),
          );
        case RemoteKeychainRecoveryCheckStatus.unsupportedNewerManifest:
          emit(
            const RemoteKeychainRecoveryState(
              status: RemoteKeychainRecoveryStatus.unsupportedNewerManifest,
            ),
          );
      }
    } on RemoteKeychainRecoveryException catch (e) {
      if (!_isActive(operationId)) return;
      _clearPendingOlder();
      emit(_failureState(e));
    } catch (e, stack) {
      log.warning(
        'Remote keychain recovery check failed',
        error: e,
        trace: stack,
      );
      if (!_isActive(operationId)) return;
      _clearPendingOlder();
      emit(_failureState(ManifestCheckFailedRecoveryException(cause: e)));
    }
  }

  Future<void> acceptRelayDisclosure() async {
    await start(acceptedThirdPartyRelayDisclosure: true);
  }

  Future<void> restoreOlderManifest() async {
    final operationId = ++_operationId;
    final importPlan = _pendingOlderImportPlan;
    if (importPlan == null) {
      emit(
        const RemoteKeychainRecoveryState(
          status: RemoteKeychainRecoveryStatus.noRecoverableManifest,
        ),
      );
      return;
    }
    final newestEventCreatedAt = _pendingOlderNewestEventCreatedAt;
    final selectedEventCreatedAt = _pendingOlderSelectedEventCreatedAt;
    _clearPendingOlder();
    await _restore(
      importPlan,
      operationId,
      newestEventCreatedAt: newestEventCreatedAt,
      selectedEventCreatedAt: selectedEventCreatedAt,
      isOlderRestore: true,
    );
  }

  void skip() {
    _operationId++;
    _clearPendingOlder();
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.skipped,
      ),
    );
  }

  Future<void> _restore(
    KeychainManifestImportPlan importPlan,
    int operationId, {
    required int? newestEventCreatedAt,
    required int? selectedEventCreatedAt,
    required bool isOlderRestore,
  }) async {
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restoring,
      ),
    );
    try {
      final summary = await _restoreManifest.execute(importPlan);
      if (!_isActive(operationId)) return;

      // Only run the DG-3 heal when something was actually restored (so a
      // flagged product's registration exists to check). healOutcome is the
      // DG-3 interpretation the UI renders; hasProductReactivationRequired
      // stays the raw restore signal.
      final restoredSomething = summary.restoredCount > 0;
      RecoveredProductsHealOutcome? healOutcome;
      if (restoredSomething) {
        healOutcome = await _healRecoveredProducts.execute(
          summary.reactivationReservationIds,
        );
        if (!_isActive(operationId)) return;
      }

      emit(
        RemoteKeychainRecoveryState(
          status: _restoreStatus(summary),
          restoredCount: summary.restoredCount,
          failedCount: summary.failedCount,
          hasProductReactivationRequired:
              summary.hasProductReactivationRequired,
          newestEventCreatedAt: newestEventCreatedAt,
          selectedEventCreatedAt: selectedEventCreatedAt,
          isOlderRestore: isOlderRestore,
          healOutcome: healOutcome?.lightningAddress,
          paymentPageHealOutcome: healOutcome?.paymentPage,
        ),
      );

      // Republish only after a LATEST-manifest restore, never after an
      // older-approved restore: a fresh NIP-33 event (newer created_at, same
      // kind+d+author) would clobber the newer unreadable manifest on the
      // relays (§3.11/§8.3). The toggle/consent/empty gates still apply in the
      // chokepoint behind this call.
      if (restoredSomething && !isOlderRestore) {
        await _publishRestoredBackup.execute();
      }
    } on RemoteKeychainRecoveryException catch (e) {
      if (!_isActive(operationId)) return;
      emit(_failureState(e));
    } catch (e, stack) {
      log.warning(
        'Remote keychain recovery restore failed',
        error: e,
        trace: stack,
      );
      if (!_isActive(operationId)) return;
      emit(_failureState(RestoreFailedRecoveryException(cause: e)));
    }
  }

  bool _isActive(int operationId) => !isClosed && operationId == _operationId;

  void _clearPendingOlder() {
    _pendingOlderImportPlan = null;
    _pendingOlderNewestEventCreatedAt = null;
    _pendingOlderSelectedEventCreatedAt = null;
  }

  RemoteKeychainRecoveryState _failureState(
    RemoteKeychainRecoveryException error,
  ) {
    return RemoteKeychainRecoveryState(
      status: switch (error.kind) {
        RemoteKeychainRecoveryErrorKind.defaultWalletUnavailable =>
          RemoteKeychainRecoveryStatus.defaultWalletUnavailable,
        RemoteKeychainRecoveryErrorKind.restoreFailed =>
          RemoteKeychainRecoveryStatus.restoreFailed,
        RemoteKeychainRecoveryErrorKind.manifestCheckFailed =>
          RemoteKeychainRecoveryStatus.failed,
      },
      failure: error,
    );
  }

  RemoteKeychainRecoveryStatus _restoreStatus(
    RemoteKeychainRecoveryRestoreSummary summary,
  ) {
    if (summary.restoredCount == 0 && summary.failedCount > 0) {
      return RemoteKeychainRecoveryStatus.restoreFailed;
    }
    if (summary.failedCount > 0) {
      return RemoteKeychainRecoveryStatus.partiallyRestored;
    }
    // P22a: zero restored and zero failed is not success - it is an empty
    // outcome, surfaced distinctly so no success screen shows zero wallets.
    if (summary.restoredCount == 0) {
      return RemoteKeychainRecoveryStatus.nothingToRestore;
    }
    return RemoteKeychainRecoveryStatus.restored;
  }
}
