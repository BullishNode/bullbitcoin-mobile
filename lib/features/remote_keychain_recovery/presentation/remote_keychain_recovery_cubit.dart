// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_error.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/check_remote_keychain_recovery_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/usecases/restore_remote_keychain_manifest_usecase.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/presentation/remote_keychain_recovery_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RemoteKeychainRecoveryCubit extends Cubit<RemoteKeychainRecoveryState> {
  final CheckRemoteKeychainRecoveryUsecase _checkRecovery;
  final RestoreRemoteKeychainManifestUsecase _restoreManifest;

  KeychainManifestImportPlan? _pendingOlderImportPlan;
  int? _pendingOlderNewestEventCreatedAt;
  int? _pendingOlderSelectedEventCreatedAt;
  int _operationId = 0;

  RemoteKeychainRecoveryCubit({
    required CheckRemoteKeychainRecoveryUsecase checkRecovery,
    required RestoreRemoteKeychainManifestUsecase restoreManifest,
  }) : _checkRecovery = checkRecovery,
       _restoreManifest = restoreManifest,
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
      final result = await _checkRecovery.execute(
        acceptedThirdPartyRelayDisclosure: acceptedThirdPartyRelayDisclosure,
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
        ),
      );
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
