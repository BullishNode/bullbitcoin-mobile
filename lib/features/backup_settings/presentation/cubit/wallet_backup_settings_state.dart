import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

enum WalletBackupSettingsOperation { idle, saving, backingUp, deleting }

final class WalletBackupSettingsState {
  final WalletBackupState? backup;
  final bool loading;
  final WalletBackupSettingsOperation operation;
  final BackupSettingsFailure? failure;
  final int failureRevision;

  const WalletBackupSettingsState({
    this.backup,
    this.loading = false,
    this.operation = WalletBackupSettingsOperation.idle,
    this.failure,
    this.failureRevision = 0,
  });

  bool get busy => operation != WalletBackupSettingsOperation.idle;

  WalletBackupSettingsState copyWith({
    WalletBackupState? backup,
    bool preserveBackup = true,
    bool? loading,
    WalletBackupSettingsOperation? operation,
    BackupSettingsFailure? failure,
    bool clearFailure = false,
    int? failureRevision,
  }) {
    return WalletBackupSettingsState(
      backup: preserveBackup ? backup ?? this.backup : backup,
      loading: loading ?? this.loading,
      operation: operation ?? this.operation,
      failure: clearFailure ? null : failure ?? this.failure,
      failureRevision: failureRevision ?? this.failureRevision,
    );
  }
}
