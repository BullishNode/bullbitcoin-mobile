import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/public/get_last_remote_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

enum WalletBackupSettingsOperation {
  idle,
  saving,
  backingUp,
  deleting,
  recovering,
}

final class WalletBackupSettingsState {
  final WalletBackupState? backup;
  final RemoteRecoveryOutcome? lastRecoveryOutcome;
  final bool loading;
  final WalletBackupSettingsOperation operation;
  final BackupSettingsFailure? failure;
  final int failureRevision;

  const WalletBackupSettingsState({
    this.backup,
    this.lastRecoveryOutcome,
    this.loading = false,
    this.operation = WalletBackupSettingsOperation.idle,
    this.failure,
    this.failureRevision = 0,
  });

  bool get busy => operation != WalletBackupSettingsOperation.idle;
  bool get canRetryRecovery =>
      !busy && (lastRecoveryOutcome?.isIncomplete ?? false);

  WalletBackupSettingsState copyWith({
    WalletBackupState? backup,
    bool preserveBackup = true,
    RemoteRecoveryOutcome? lastRecoveryOutcome,
    bool clearLastRecoveryOutcome = false,
    bool? loading,
    WalletBackupSettingsOperation? operation,
    BackupSettingsFailure? failure,
    bool clearFailure = false,
    int? failureRevision,
  }) {
    return WalletBackupSettingsState(
      backup: preserveBackup ? backup ?? this.backup : backup,
      lastRecoveryOutcome: clearLastRecoveryOutcome
          ? null
          : lastRecoveryOutcome ?? this.lastRecoveryOutcome,
      loading: loading ?? this.loading,
      operation: operation ?? this.operation,
      failure: clearFailure ? null : failure ?? this.failure,
      failureRevision: failureRevision ?? this.failureRevision,
    );
  }
}
