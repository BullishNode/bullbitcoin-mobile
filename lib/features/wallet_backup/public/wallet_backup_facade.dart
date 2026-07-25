export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart'
    show WalletBackupState;
export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_manifest_import.dart'
    show WalletBackupManifestImport;
export 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart'
    show WalletMetadataRecoveryFence;

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_manifest_import.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_manifest_import_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/get_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/watch_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/watchers/wallet_backup_coordinator.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

class WalletBackupFacade {
  final GetWalletBackupStateUsecase _getState;
  final WatchWalletBackupStateUsecase _watchState;
  final SetWalletBackupEnabledUsecase _setEnabled;
  final DeleteWalletBackupUsecase _delete;
  final FetchWalletBackupManifestImportUsecase _fetchManifestImport;
  final WalletBackupCoordinator _coordinator;

  const WalletBackupFacade({
    required this._getState,
    required this._watchState,
    required this._setEnabled,
    required this._delete,
    required this._fetchManifestImport,
    required this._coordinator,
  });

  @useResult
  Future<Result<WalletBackupState, WalletBackupFailure>> getState() {
    return _getState.execute();
  }

  @useResult
  Stream<Result<WalletBackupState, WalletBackupFailure>> watchState() {
    return _watchState.execute();
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) async {
    final result = await _setEnabled.execute(enabled);
    if (result case Err()) return result;
    if (!enabled) return result;
    return _coordinator.publish();
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> backupNow() {
    return _coordinator.publish();
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> deleteRemoteBackup({
    required bool confirmed,
  }) async {
    await _coordinator.waitForIdle();
    return _delete.execute(confirmed: confirmed);
  }

  @useResult
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>
  fetchManifestImport() {
    return _fetchManifestImport.execute();
  }

  /// Holds unified-backup publication while remote recovery restores local
  /// keychain and metadata state.
  Future<WalletMetadataRecoveryFence> beginRecoveryLease() {
    return _coordinator.beginRecoveryLease();
  }
}
