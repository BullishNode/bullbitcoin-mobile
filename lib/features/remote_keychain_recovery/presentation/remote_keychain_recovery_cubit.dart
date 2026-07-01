// ignore_for_file: prefer_initializing_formals

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
  int _operationId = 0;

  RemoteKeychainRecoveryCubit({
    required CheckRemoteKeychainRecoveryUsecase checkRecovery,
    required RestoreRemoteKeychainManifestUsecase restoreManifest,
  }) : _checkRecovery = checkRecovery,
       _restoreManifest = restoreManifest,
       super(const RemoteKeychainRecoveryState());

  Future<void> start({bool acceptedThirdPartyRelayDisclosure = false}) async {
    final operationId = ++_operationId;
    _pendingOlderImportPlan = null;
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
          await _restore(importPlan, operationId);
        case RemoteKeychainRecoveryCheckStatus.olderManifestAvailable:
          _pendingOlderImportPlan = result.importPlan;
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
      }
    } on RemoteKeychainRecoveryException catch (e) {
      if (!_isActive(operationId)) return;
      _pendingOlderImportPlan = null;
      emit(_failureState(e));
    } catch (e) {
      if (!_isActive(operationId)) return;
      _pendingOlderImportPlan = null;
      emit(
        RemoteKeychainRecoveryState(
          status: RemoteKeychainRecoveryStatus.failed,
          error: e,
        ),
      );
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
    _pendingOlderImportPlan = null;
    await _restore(importPlan, operationId);
  }

  void skip() {
    _operationId++;
    _pendingOlderImportPlan = null;
    emit(
      const RemoteKeychainRecoveryState(
        status: RemoteKeychainRecoveryStatus.skipped,
      ),
    );
  }

  Future<void> _restore(
    KeychainManifestImportPlan importPlan,
    int operationId,
  ) async {
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
        ),
      );
    } on RemoteKeychainRecoveryException catch (e) {
      if (!_isActive(operationId)) return;
      emit(_failureState(e));
    } catch (e) {
      if (!_isActive(operationId)) return;
      emit(
        RemoteKeychainRecoveryState(
          status: RemoteKeychainRecoveryStatus.failed,
          error: e,
        ),
      );
    }
  }

  bool _isActive(int operationId) => !isClosed && operationId == _operationId;

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
      error: error,
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
    return RemoteKeychainRecoveryStatus.restored;
  }
}
