export 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart'
    show WalletBackupState;
export 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_backup/domain/entities/wallet_backup_state.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/get_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/usecases/watch_wallet_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/domain/wallet_backup_failure.dart';
import 'package:meta/meta.dart';

class WalletBackupFacade {
  final GetWalletBackupStateUsecase _getState;
  final WatchWalletBackupStateUsecase _watchState;
  final SetWalletBackupEnabledUsecase _setEnabled;
  final BackupWalletNowUsecase _backupNow;
  final DeleteWalletBackupUsecase _delete;

  const WalletBackupFacade({
    required this._getState,
    required this._watchState,
    required this._setEnabled,
    required this._backupNow,
    required this._delete,
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
  Future<Result<void, WalletBackupFailure>> setEnabled(bool enabled) {
    return _setEnabled.execute(enabled);
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> backupNow() {
    return _backupNow.execute();
  }

  @useResult
  Future<Result<void, WalletBackupFailure>> deleteRemoteBackup({
    required bool confirmed,
  }) {
    return _delete.execute(confirmed: confirmed);
  }
}
