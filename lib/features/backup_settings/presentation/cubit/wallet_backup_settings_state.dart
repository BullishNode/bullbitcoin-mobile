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
  bool get canRetryRecovery => !busy && (backup?.recoveryBlocked ?? false);

  /// True once a write has been ATTEMPTED since the last success and the
  /// backup is still dirty: the write was rejected, not queued. A backup that
  /// is merely waiting for its first attempt is not this — reporting it as
  /// pending forever is exactly the dishonesty this separates out.
  bool get metadataWriteRejected {
    final state = backup;
    if (state == null || !state.dirty) return false;
    final attemptedAt = state.lastAttemptedAt;
    if (attemptedAt == null) return false;
    return attemptedAt > (state.lastSucceededAt ?? 0);
  }

  /// The one condition worth surfacing on the Backup Settings status row: the
  /// backup cannot make progress until the user does something (update the
  /// app, retry recovery) or a rejected write is retried.
  bool get metadataAttentionNeeded {
    final state = backup;
    if (state == null) return false;
    return state.unsupportedVersion != null ||
        state.recoveryBlocked ||
        metadataWriteRejected;
  }

  /// When the last write actually landed, or null when none ever has. Never
  /// derived from an attempt — only from an observed success.
  DateTime? get metadataLastBackedUpAt {
    final succeededAt = backup?.lastSucceededAt;
    if (succeededAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      succeededAt * 1000,
      isUtc: true,
    ).toLocal();
  }

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
