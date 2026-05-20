import 'package:bb_mobile/features/wallet_manifest/application/usecases/audit_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/check_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/get_wallet_manifest_public_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/save_wallet_manifest_payload_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WalletManifestSettingsCubit extends Cubit<WalletManifestSettingsState> {
  final GetWalletManifestPublicKeyUsecase _getPublicKey;
  final CheckRemoteWalletManifestUsecase _checkRemoteManifest;
  final PublishLocalWalletManifestUsecase _publishLocalManifest;
  final RestoreRemoteWalletManifestUsecase _restoreRemoteManifest;
  final SaveWalletManifestPayloadUsecase _saveWalletManifestPayload;
  final AuditRemoteWalletManifestUsecase _auditRemoteWalletManifest;

  WalletManifestSettingsCubit({
    required GetWalletManifestPublicKeyUsecase getPublicKey,
    required CheckRemoteWalletManifestUsecase checkRemoteManifest,
    required PublishLocalWalletManifestUsecase publishLocalManifest,
    required RestoreRemoteWalletManifestUsecase restoreRemoteManifest,
    required SaveWalletManifestPayloadUsecase saveWalletManifestPayload,
    required AuditRemoteWalletManifestUsecase auditRemoteWalletManifest,
  }) : _getPublicKey = getPublicKey,
       _checkRemoteManifest = checkRemoteManifest,
       _publishLocalManifest = publishLocalManifest,
       _restoreRemoteManifest = restoreRemoteManifest,
       _saveWalletManifestPayload = saveWalletManifestPayload,
       _auditRemoteWalletManifest = auditRemoteWalletManifest,
       super(const WalletManifestSettingsState());

  Future<void> load() async {
    emit(state.copyWith(loading: true, failed: false, clearNpub: true));
    try {
      final npub = await _getPublicKey.execute();
      if (isClosed) return;
      emit(state.copyWith(loading: false, failed: false, npub: npub));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, failed: true));
    }
  }

  Future<void> checkRemoteManifest() async {
    if (state.manifestOperationInProgress) return;

    emit(
      state.copyWith(
        remoteCheckStatus: WalletManifestRemoteCheckStatus.loading,
        clearRemoteManifest: true,
        publishStatus: WalletManifestPublishStatus.idle,
        clearPublishedManifest: true,
        saveStatus: WalletManifestSaveStatus.idle,
        manualRestoreStatus: WalletManifestManualRestoreStatus.idle,
        clearManualRestore: true,
        auditStatus: WalletManifestAuditStatus.idle,
        clearAudit: true,
      ),
    );
    try {
      final result = await _checkRemoteManifest.execute();
      if (isClosed) return;
      if (result == null) {
        emit(
          state.copyWith(
            remoteCheckStatus: WalletManifestRemoteCheckStatus.missing,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          remoteCheckStatus: WalletManifestRemoteCheckStatus.loaded,
          remoteManifestJson: result.manifestJson,
          remoteManifestAccountCount: result.accountCount,
          remoteManifestCreatedAt: result.createdAt,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          remoteCheckStatus: WalletManifestRemoteCheckStatus.failed,
        ),
      );
    }
  }

  Future<void> publishLocalManifest() async {
    if (state.manifestOperationInProgress) return;

    emit(
      state.copyWith(
        publishStatus: WalletManifestPublishStatus.loading,
        clearPublishedManifest: true,
        remoteCheckStatus: WalletManifestRemoteCheckStatus.idle,
        clearRemoteManifest: true,
        saveStatus: WalletManifestSaveStatus.idle,
        manualRestoreStatus: WalletManifestManualRestoreStatus.idle,
        clearManualRestore: true,
        auditStatus: WalletManifestAuditStatus.idle,
        clearAudit: true,
      ),
    );
    try {
      final accountCount = await _publishLocalManifest.execute();
      if (isClosed) return;
      emit(
        state.copyWith(
          publishStatus: WalletManifestPublishStatus.succeeded,
          publishedManifestAccountCount: accountCount,
          publishedManifestCreatedAt: _nowEpochSeconds(),
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(publishStatus: WalletManifestPublishStatus.failed));
    }
  }

  Future<void> restoreRemoteManifest() async {
    if (state.manifestOperationInProgress) return;

    emit(
      state.copyWith(
        manualRestoreStatus: WalletManifestManualRestoreStatus.loading,
        clearManualRestore: true,
        remoteCheckStatus: WalletManifestRemoteCheckStatus.idle,
        clearRemoteManifest: true,
        saveStatus: WalletManifestSaveStatus.idle,
        publishStatus: WalletManifestPublishStatus.idle,
        clearPublishedManifest: true,
        auditStatus: WalletManifestAuditStatus.idle,
        clearAudit: true,
      ),
    );
    try {
      final result = await _restoreRemoteManifest.execute();
      if (isClosed) return;
      if (result == null) {
        emit(
          state.copyWith(
            manualRestoreStatus: WalletManifestManualRestoreStatus.missing,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          manualRestoreStatus: result.complete
              ? WalletManifestManualRestoreStatus.completed
              : WalletManifestManualRestoreStatus.needsAttention,
          manualRestoreRestoredCount: result.restoredCount,
          manualRestoreAlreadyPresentCount: result.alreadyPresentCount,
          manualRestoreSkippedCount: result.skippedCount,
          manualRestoreFailedCount: result.failedCount,
          manualRestoreWalletStateMayHaveChanged:
              result.walletStateMayHaveChanged,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          manualRestoreStatus: WalletManifestManualRestoreStatus.failed,
        ),
      );
    }
  }

  Future<void> saveRemoteManifest() async {
    if (state.manifestOperationInProgress || state.remoteManifestJson == null) {
      return;
    }

    emit(state.copyWith(saveStatus: WalletManifestSaveStatus.loading));
    try {
      final saved = await _saveWalletManifestPayload.execute(
        manifestJson: state.remoteManifestJson!,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          saveStatus: saved
              ? WalletManifestSaveStatus.succeeded
              : WalletManifestSaveStatus.cancelled,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(saveStatus: WalletManifestSaveStatus.failed));
    }
  }

  Future<void> auditRemoteManifest() async {
    if (state.manifestOperationInProgress) return;

    emit(
      state.copyWith(
        auditStatus: WalletManifestAuditStatus.loading,
        clearAudit: true,
        remoteCheckStatus: WalletManifestRemoteCheckStatus.idle,
        clearRemoteManifest: true,
        publishStatus: WalletManifestPublishStatus.idle,
        clearPublishedManifest: true,
        saveStatus: WalletManifestSaveStatus.idle,
        manualRestoreStatus: WalletManifestManualRestoreStatus.idle,
        clearManualRestore: true,
      ),
    );
    try {
      final result = await _auditRemoteWalletManifest.execute();
      if (isClosed) return;
      if (!result.remoteManifestFound) {
        emit(
          state.copyWith(
            auditStatus: WalletManifestAuditStatus.missing,
            auditMatchingCount: result.matchingCount,
            auditMissingLocalCount: result.missingLocalCount,
            auditMissingRemoteCount: result.missingRemoteCount,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          auditStatus: result.matches
              ? WalletManifestAuditStatus.matches
              : WalletManifestAuditStatus.differs,
          auditMatchingCount: result.matchingCount,
          auditMissingLocalCount: result.missingLocalCount,
          auditMissingRemoteCount: result.missingRemoteCount,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(auditStatus: WalletManifestAuditStatus.failed));
    }
  }

  int _nowEpochSeconds() =>
      DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
}
