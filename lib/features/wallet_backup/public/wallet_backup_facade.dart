export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart'
    show WalletBackupState;
export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_manifest_import.dart'
    show WalletBackupManifestImport;
export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote_identity.dart'
    show WalletBackupRemoteIdentity;
export 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
export 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_lifecycle_lease.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_manifest_import.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_remote_identity.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_manifest_import_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/fetch_wallet_backup_remote_identity_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/get_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_recovery_blocked_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/watch_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_lifecycle_lease.dart';
import 'package:bb_mobile/features/wallet_backup/watchers/wallet_backup_coordinator.dart';
import 'package:meta/meta.dart';

class WalletBackupFacade {
  final GetWalletBackupStateUsecase _getState;
  final WatchWalletBackupStateUsecase _watchState;
  final SetWalletBackupEnabledUsecase _setEnabled;
  final DeleteWalletBackupUsecase _delete;
  final FetchWalletBackupManifestImportUsecase _fetchManifestImport;
  final FetchWalletBackupRemoteIdentityUsecase _fetchRemoteIdentity;
  final SetWalletBackupRecoveryBlockedUsecase _setRecoveryBlocked;
  final WalletBackupCoordinator _coordinator;

  const WalletBackupFacade({
    required this._getState,
    required this._watchState,
    required this._setEnabled,
    required this._delete,
    required this._fetchManifestImport,
    required this._fetchRemoteIdentity,
    required this._setRecoveryBlocked,
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
    return _coordinator.publishLatest();
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> deleteRemoteBackup({
    required bool confirmed,
  }) async {
    if (!confirmed) return _delete.execute(confirmed: false);
    final lease = await _coordinator.beginDeletionLease();
    try {
      return await _delete.execute(confirmed: true);
    } finally {
      lease.close();
    }
  }

  @useResult
  Future<Result<WalletBackupManifestImport?, WalletBackupFailure>>
  fetchManifestImport() {
    return _fetchManifestImport.execute();
  }

  @useResult
  Future<Result<WalletBackupRemoteIdentity, WalletBackupFailure>>
  fetchRemoteIdentity() => _fetchRemoteIdentity.execute();

  @useResult
  Future<Result<void, WalletBackupFailure>> setRecoveryBlocked(bool blocked) =>
      _setRecoveryBlocked.execute(blocked);

  /// Holds unified-backup publication while remote recovery restores local
  /// keychain and metadata state.
  Future<WalletBackupLifecycleLease> beginRecoveryLease({Duration? timeout}) {
    return _coordinator.beginRecoveryLease(timeout: timeout);
  }
}
