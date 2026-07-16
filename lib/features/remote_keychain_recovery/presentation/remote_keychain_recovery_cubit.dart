import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/recovered_products_heal_outcome.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/heal_recovered_products_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/apply_remote_wallet_metadata_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/begin_wallet_metadata_recovery_session_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/load_automated_backup_consent_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/publish_restored_keychain_backup_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RemoteKeychainRecoveryCubit extends Cubit<RemoteKeychainRecoveryState> {
  final CheckRemoteKeychainRecoveryUsecase _checkRecovery;
  final RestoreRemoteKeychainManifestUsecase _restoreManifest;
  final LoadAutomatedBackupConsentUsecase _loadConsent;
  final HealRecoveredProductsUsecase _healRecoveredProducts;
  final PublishRestoredKeychainBackupUsecase _publishRestoredBackup;
  final CheckRemoteWalletMetadataRecoveryUsecase _checkMetadataRecovery;
  final ApplyRemoteWalletMetadataRecoveryUsecase _applyMetadataRecovery;
  final BeginWalletMetadataRecoverySessionUsecase _beginMetadataSession;

  KeychainManifestImportPlan? _pendingOlderImportPlan;
  int? _pendingOlderNewestEventCreatedAt;
  int? _pendingOlderSelectedEventCreatedAt;
  WalletMetadataRecoveryPlan? _pendingMetadataPlan;
  RemoteKeychainRecoveryState? _stateBeforeMetadata;
  WalletMetadataPublicationSuppression? _metadataSession;
  Set<String> _createdWalletRefs = const {};
  int _operationId = 0;

  RemoteKeychainRecoveryCubit({
    required this._checkRecovery,
    required this._restoreManifest,
    required this._loadConsent,
    required this._healRecoveredProducts,
    required this._publishRestoredBackup,
    required this._checkMetadataRecovery,
    required this._applyMetadataRecovery,
    required this._beginMetadataSession,
  }) : super(const RemoteKeychainRecoveryState());

  Future<void> start({bool acceptedThirdPartyRelayDisclosure = false}) async {
    final operationId = ++_operationId;
    _clearPendingOlder();
    _clearMetadataRecovery();
    _createdWalletRefs = const {};
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
          await startMetadataRecovery();
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
          await startMetadataRecovery();
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
        error: StateError(e.runtimeType.toString()),
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

  Future<void> startMetadataRecovery() async {
    final operationId = ++_operationId;
    _pendingMetadataPlan = null;
    _stateBeforeMetadata = _isKeychainTerminal(state.status) ? state : null;
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.checkingMetadata,
      ),
    );
    try {
      if (!_hasOpenMetadataSession) {
        _closeMetadataSession();
        final session = await _beginMetadataSession.execute();
        if (!_isActive(operationId)) {
          session.close();
          return;
        }
        _metadataSession = session;
      }
      await _checkMetadata(operationId);
    } on Exception catch (error, stack) {
      if (_isActive(operationId)) _emitMetadataFailure(error, stack);
    }
  }

  Future<void> _restoreMetadata(int operationId) async {
    final plan = _pendingMetadataPlan;
    if (plan == null || !_hasOpenMetadataSession) {
      _emitMetadataFailure(StateError('Metadata recovery session is invalid'));
      return;
    }
    _pendingMetadataPlan = null;
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.restoringMetadata,
      ),
    );
    try {
      final result = await _applyMetadataRecovery.execute(
        plan: plan,
        createdWalletRefs: _createdWalletRefs,
      );
      if (!_isActive(operationId)) return;
      switch (result) {
        case Ok(:final value):
          _closeMetadataSession();
          final keychainState = _stateBeforeMetadata;
          _stateBeforeMetadata = null;
          final partial =
              value.publicationBlocked ||
              value.preservedLocalConflictCount > 0 ||
              value.deferredMissingWalletCount > 0 ||
              value.unsupportedCount > 0 ||
              value.invalidRecordCount > 0 ||
              value.failedStorageCount > 0;
          emit(
            RemoteKeychainRecoveryState(
              status: partial
                  ? RemoteKeychainRecoveryStatus.metadataPartiallyRestored
                  : RemoteKeychainRecoveryStatus.metadataRestored,
              restoredCount: keychainState?.restoredCount ?? 0,
              failedCount: keychainState?.failedCount ?? 0,
              hasProductReactivationRequired:
                  keychainState?.hasProductReactivationRequired ?? false,
              newestEventCreatedAt: keychainState?.newestEventCreatedAt,
              selectedEventCreatedAt: keychainState?.selectedEventCreatedAt,
              isOlderRestore: keychainState?.isOlderRestore ?? false,
              healOutcome: keychainState?.healOutcome,
              paymentPageHealOutcome: keychainState?.paymentPageHealOutcome,
              posHealOutcome: keychainState?.posHealOutcome,
              metadataRestoredCount: value.restoredCount,
              metadataAlreadyPresentCount: value.alreadyPresentCount,
              metadataConflictCount: value.preservedLocalConflictCount,
              metadataDeferredCount: value.deferredMissingWalletCount,
              metadataUnsupportedCount: value.unsupportedCount,
              metadataInvalidCount: value.invalidRecordCount,
              metadataFailedCount: value.failedStorageCount,
              metadataIsOlder:
                  value.status ==
                      WalletMetadataRecoveryApplyStatus.olderComplete ||
                  value.status ==
                      WalletMetadataRecoveryApplyStatus.olderIncomplete,
            ),
          );
        case Err(:final failure):
          _emitMetadataFailure(failure);
      }
    } on Exception catch (error, stack) {
      if (_isActive(operationId)) _emitMetadataFailure(error, stack);
    }
  }

  Future<void> skip() async {
    _operationId++;
    _clearPendingOlder();
    _clearMetadataRecovery();
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.skipped,
      ),
    );
    await startMetadataRecovery();
  }

  Future<void> _checkMetadata(int operationId) async {
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.checkingMetadata,
      ),
    );
    try {
      final result = await _checkMetadataRecovery.execute();
      if (!_isActive(operationId)) return;
      switch (result) {
        case Err(:final failure):
          _emitMetadataFailure(failure);
        case Ok(:final value):
          switch (value.status) {
            case WalletMetadataRecoveryStatus.latestSnapshot ||
                WalletMetadataRecoveryStatus
                    .latestSnapshotWithUnsupportedMetadata ||
                WalletMetadataRecoveryStatus.olderSnapshot ||
                WalletMetadataRecoveryStatus
                    .olderSnapshotWithUnsupportedMetadata:
              final plan = value.plan;
              if (plan == null) {
                _emitMetadataFailure(
                  StateError('Metadata recovery plan is missing'),
                );
                return;
              }
              _pendingMetadataPlan = plan;
              await _restoreMetadata(operationId);
            case WalletMetadataRecoveryStatus.noSnapshotFound:
              _emitMetadataTerminal(
                RemoteKeychainRecoveryStatus.metadataNoSnapshot,
              );
            case WalletMetadataRecoveryStatus.relaysUnavailable:
              _emitMetadataTerminal(
                RemoteKeychainRecoveryStatus.metadataRelaysUnavailable,
              );
            case WalletMetadataRecoveryStatus.noCompleteSnapshot:
              _emitMetadataTerminal(
                RemoteKeychainRecoveryStatus.metadataNoCompleteSnapshot,
              );
            case WalletMetadataRecoveryStatus.unsupportedNewerEnvelope:
              _emitMetadataTerminal(
                RemoteKeychainRecoveryStatus.metadataUpdateRequired,
              );
          }
      }
    } on Exception catch (error, stack) {
      if (_isActive(operationId)) _emitMetadataFailure(error, stack);
    }
  }

  void _emitMetadataTerminal(RemoteKeychainRecoveryStatus status) {
    final fallback = status == RemoteKeychainRecoveryStatus.metadataNoSnapshot
        ? _stateBeforeMetadata
        : null;
    _pendingMetadataPlan = null;
    _stateBeforeMetadata = null;
    _closeMetadataSession();
    emit(fallback ?? RemoteKeychainRecoveryState(status: status));
  }

  void _emitMetadataFailure([Object? failure, StackTrace? stack]) {
    if (failure != null) {
      log.warning(
        'Remote wallet metadata recovery failed',
        error: StateError(failure.runtimeType.toString()),
        trace: stack,
      );
    }
    _emitMetadataTerminal(RemoteKeychainRecoveryStatus.metadataFailed);
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
    WalletMetadataPublicationSuppression? metadataSuppression;
    try {
      metadataSuppression = await _beginMetadataSession.execute();
      if (!_isActive(operationId)) return;
      final summary = await _restoreManifest.execute(importPlan);
      if (!_isActive(operationId)) return;
      _createdWalletRefs = Set.unmodifiable(summary.createdWalletRefs);

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

      final restoreStatus = _restoreStatus(summary);
      // Metadata can still be restored for wallets that were successfully
      // created during a partial keychain restore. An all-failed keychain
      // restore has no safe materialization boundary to continue from.
      final metadataRecoveryCanProceed =
          summary.failedCount == 0 || restoredSomething;
      if (metadataRecoveryCanProceed) {
        _closeMetadataSession();
        _metadataSession = metadataSuppression;
        metadataSuppression = null;
      }
      emit(
        RemoteKeychainRecoveryState(
          status: restoreStatus,
          restoredCount: summary.restoredCount,
          failedCount: summary.failedCount,
          hasProductReactivationRequired:
              summary.hasProductReactivationRequired,
          newestEventCreatedAt: newestEventCreatedAt,
          selectedEventCreatedAt: selectedEventCreatedAt,
          isOlderRestore: isOlderRestore,
          healOutcome: healOutcome?.lightningAddress,
          paymentPageHealOutcome: healOutcome?.paymentPage,
          posHealOutcome: healOutcome?.pos,
        ),
      );

      // Republish only after a LATEST-manifest restore, never after an
      // older-approved restore: a fresh NIP-33 event (newer created_at, same
      // kind+d+author) would clobber the newer unreadable manifest on the
      // relays (§3.11/§8.3). The toggle/consent/empty gates still apply in the
      // chokepoint behind this call.
      if (restoredSomething && !isOlderRestore) {
        try {
          await _publishRestoredBackup.execute();
        } on Exception catch (_, stack) {
          log.warning(
            'Post-recovery keychain backup publication failed',
            error: StateError('Keychain backup publication failed'),
            trace: stack,
          );
        }
      }
      if (metadataRecoveryCanProceed) {
        await startMetadataRecovery();
      }
    } on RemoteKeychainRecoveryException catch (e) {
      if (!_isActive(operationId)) return;
      emit(_failureState(e));
    } catch (e, stack) {
      log.warning(
        'Remote keychain recovery restore failed',
        error: StateError(e.runtimeType.toString()),
        trace: stack,
      );
      if (!_isActive(operationId)) return;
      emit(_failureState(RestoreFailedRecoveryException(cause: e)));
    } finally {
      metadataSuppression?.close();
    }
  }

  bool _isActive(int operationId) => !isClosed && operationId == _operationId;

  void _clearPendingOlder() {
    _pendingOlderImportPlan = null;
    _pendingOlderNewestEventCreatedAt = null;
    _pendingOlderSelectedEventCreatedAt = null;
  }

  void _clearMetadataRecovery() {
    _pendingMetadataPlan = null;
    _stateBeforeMetadata = null;
    _closeMetadataSession();
  }

  bool _isKeychainTerminal(RemoteKeychainRecoveryStatus status) =>
      switch (status) {
        RemoteKeychainRecoveryStatus.restored ||
        RemoteKeychainRecoveryStatus.partiallyRestored ||
        RemoteKeychainRecoveryStatus.nothingToRestore ||
        RemoteKeychainRecoveryStatus.noManifestFound ||
        RemoteKeychainRecoveryStatus.noRecoverableManifest ||
        RemoteKeychainRecoveryStatus.skipped => true,
        _ => false,
      };

  void _closeMetadataSession() {
    _metadataSession?.close();
    _metadataSession = null;
  }

  bool get _hasOpenMetadataSession =>
      _metadataSession != null && !_metadataSession!.isClosed;

  @override
  Future<void> close() {
    _operationId++;
    _clearMetadataRecovery();
    return super.close();
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
