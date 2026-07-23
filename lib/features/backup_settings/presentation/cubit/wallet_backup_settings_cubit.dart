import 'dart:async';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/backup_wallet_now_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/delete_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/retry_wallet_backup_recovery_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/set_wallet_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/watch_wallet_backup_usecase.dart';
import 'package:bb_mobile/features/backup_settings/presentation/cubit/wallet_backup_settings_state.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/get_last_remote_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

final class WalletBackupSettingsCubit extends Cubit<WalletBackupSettingsState> {
  final WatchWalletBackupUsecase _watchBackup;
  final SetWalletBackupEnabledUsecase _setBackupEnabled;
  final BackupWalletNowUsecase _backupNow;
  final DeleteWalletBackupUsecase _deleteBackup;
  final GetLastRemoteRecoveryOutcomeUsecase? _getLastRecoveryOutcome;
  final RetryWalletBackupRecoveryUsecase? _retryRecovery;
  StreamSubscription<Result<WalletBackupState, BackupSettingsFailure>>?
  _subscription;
  bool _closing = false;

  WalletBackupSettingsCubit(
    this._watchBackup,
    this._setBackupEnabled,
    this._backupNow,
    this._deleteBackup, [
    this._getLastRecoveryOutcome,
    this._retryRecovery,
  ]) : super(const WalletBackupSettingsState());

  Future<void> load() async {
    if (_inactive) return;
    emit(state.copyWith(loading: true, clearFailure: true));
    await _refreshRecoveryOutcome();
    await _subscription?.cancel();
    if (_inactive) return;
    _subscription = _watchBackup.execute().listen(
      (result) {
        if (_inactive) return;
        switch (result) {
          case Ok(:final value):
            emit(
              state.copyWith(backup: value, loading: false, clearFailure: true),
            );
          case Err(:final failure):
            _emitFailure(failure, loading: false);
        }
      },
      onError: (_, _) {
        if (_inactive) return;
        _emitFailure(const BackupSettingsUnexpectedFailure(), loading: false);
      },
    );
  }

  Future<void> setEnabled(bool enabled) {
    return _run(
      WalletBackupSettingsOperation.saving,
      () => _setBackupEnabled.execute(enabled),
    );
  }

  Future<void> backupNow() {
    return _run(WalletBackupSettingsOperation.backingUp, _backupNow.execute);
  }

  Future<void> deleteRemoteBackup() {
    return _run(WalletBackupSettingsOperation.deleting, _deleteBackup.execute);
  }

  Future<void> retryRecovery() async {
    final retryRecovery = _retryRecovery;
    if (_inactive || !state.canRetryRecovery || retryRecovery == null) return;
    emit(
      state.copyWith(
        operation: WalletBackupSettingsOperation.recovering,
        clearFailure: true,
      ),
    );
    try {
      await retryRecovery.execute();
    } catch (_) {
      if (!_inactive) {
        _emitFailure(const BackupSettingsUnexpectedFailure());
      }
    } finally {
      await _refreshRecoveryOutcome();
      if (!_inactive) {
        emit(state.copyWith(operation: WalletBackupSettingsOperation.idle));
      }
    }
  }

  Future<void> _run(
    WalletBackupSettingsOperation operation,
    Future<Result<void, BackupSettingsFailure>> Function() action,
  ) async {
    if (_inactive || state.busy) return;
    emit(state.copyWith(operation: operation, clearFailure: true));
    try {
      final result = await action();
      if (_inactive) return;
      if (result case Err(:final failure)) {
        _emitFailure(failure);
      }
    } catch (_) {
      if (_inactive) return;
      _emitFailure(const BackupSettingsUnexpectedFailure());
    } finally {
      if (!_inactive) {
        emit(state.copyWith(operation: WalletBackupSettingsOperation.idle));
      }
    }
  }

  void _emitFailure(BackupSettingsFailure failure, {bool? loading}) {
    if (_inactive) return;
    emit(
      state.copyWith(
        loading: loading,
        failure: failure,
        failureRevision: state.failureRevision + 1,
      ),
    );
  }

  Future<void> _refreshRecoveryOutcome() async {
    final getLastRecoveryOutcome = _getLastRecoveryOutcome;
    if (getLastRecoveryOutcome == null) return;
    try {
      final outcome = await getLastRecoveryOutcome.execute();
      if (_inactive) return;
      emit(
        outcome == null
            ? state.copyWith(clearLastRecoveryOutcome: true)
            : state.copyWith(lastRecoveryOutcome: outcome),
      );
    } catch (_) {
      // Recovery history is auxiliary; keep the current backup state usable.
    }
  }

  bool get _inactive => _closing || isClosed;

  @override
  Future<void> close() async {
    if (_closing || isClosed) return;
    _closing = true;
    await _subscription?.cancel();
    _subscription = null;
    return super.close();
  }
}
