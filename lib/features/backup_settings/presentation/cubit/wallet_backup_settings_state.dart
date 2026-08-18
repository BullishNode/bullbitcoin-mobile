import 'package:bb_mobile/features/backup_settings/domain/backup_settings_failure.dart';
import 'package:bb_mobile/features/backup_settings/domain/usecases/get_last_wallet_backup_recovery_outcome_usecase.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';

enum WalletBackupSettingsOperation {
  idle,
  saving,
  backingUp,
  deleting,
  recovering,
}

enum WalletBackupRecoveryResultKind {
  restored,
  nothingToRestore,
  noBackup,
  incomplete,
  failed,
}

final class WalletBackupRecoveryResultSummary {
  final WalletBackupRecoveryResultKind kind;
  final int restoredCount;
  final int failedCount;

  const WalletBackupRecoveryResultSummary({
    required this.kind,
    required this.restoredCount,
    required this.failedCount,
  });

  bool get failed =>
      kind == WalletBackupRecoveryResultKind.incomplete ||
      kind == WalletBackupRecoveryResultKind.failed;
}

final class WalletBackupSettingsState {
  final WalletBackupState? backup;
  final WalletBackupRecoveryOutcome? lastRecoveryOutcome;
  final bool recoveryRetryAttempted;
  final bool recoveryRetryFailed;
  final bool loading;
  final WalletBackupSettingsOperation operation;
  final BackupSettingsFailure? failure;
  final int failureRevision;

  const WalletBackupSettingsState({
    this.backup,
    this.lastRecoveryOutcome,
    this.recoveryRetryAttempted = false,
    this.recoveryRetryFailed = false,
    this.loading = false,
    this.operation = WalletBackupSettingsOperation.idle,
    this.failure,
    this.failureRevision = 0,
  });

  bool get busy => operation != WalletBackupSettingsOperation.idle;
  bool get canRetryRecovery => !busy && (backup?.recoveryBlocked ?? false);

  WalletBackupRecoveryResultSummary? get recoveryRetryResult {
    if (!recoveryRetryAttempted) return null;
    if (recoveryRetryFailed) {
      return const WalletBackupRecoveryResultSummary(
        kind: WalletBackupRecoveryResultKind.failed,
        restoredCount: 0,
        failedCount: 0,
      );
    }
    final outcome = lastRecoveryOutcome;
    if (outcome == null) return null;
    return WalletBackupRecoveryResultSummary(
      kind: switch (outcome.status) {
        WalletBackupRecoveryOutcomeStatus.restored =>
          WalletBackupRecoveryResultKind.restored,
        WalletBackupRecoveryOutcomeStatus.nothingToRestore =>
          WalletBackupRecoveryResultKind.nothingToRestore,
        WalletBackupRecoveryOutcomeStatus.noBackup =>
          WalletBackupRecoveryResultKind.noBackup,
        WalletBackupRecoveryOutcomeStatus.partiallyRestored ||
        WalletBackupRecoveryOutcomeStatus.timedOut =>
          WalletBackupRecoveryResultKind.incomplete,
        _ => WalletBackupRecoveryResultKind.failed,
      },
      restoredCount: outcome.restoredCount,
      failedCount: outcome.failedCount,
    );
  }

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
    WalletBackupRecoveryOutcome? lastRecoveryOutcome,
    bool clearLastRecoveryOutcome = false,
    bool? recoveryRetryAttempted,
    bool? recoveryRetryFailed,
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
      recoveryRetryAttempted:
          recoveryRetryAttempted ?? this.recoveryRetryAttempted,
      recoveryRetryFailed: recoveryRetryFailed ?? this.recoveryRetryFailed,
      loading: loading ?? this.loading,
      operation: operation ?? this.operation,
      failure: clearFailure ? null : failure ?? this.failure,
      failureRevision: failureRevision ?? this.failureRevision,
    );
  }
}
