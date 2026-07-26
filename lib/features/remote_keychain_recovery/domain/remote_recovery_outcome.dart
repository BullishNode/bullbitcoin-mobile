import 'dart:convert';

import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';

export 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart'
    show RemoteKeychainRecoveryStatus;

/// The persisted outcome of the most recent remote keychain recovery pass.
///
/// Recovery itself stays silent (onboarding and RecoverBull continue
/// regardless of the result), so this record is the ONLY way a later screen —
/// the unified wallet-backup settings page — can know that a restore was partial or
/// timed out and offer the manual retry. It is deliberately minimal and
/// sanitized: a status, a timestamp, and counts. Never wallet names, manifest
/// entries, or any identifier — this must not become a recovery-payload echo.
final class RemoteRecoveryOutcome {
  final RemoteKeychainRecoveryStatus status;

  /// Unix seconds when the recovery pass finished.
  final int atUnix;
  final int restoredCount;
  final int failedCount;

  const RemoteRecoveryOutcome({
    required this.status,
    required this.atUnix,
    required this.restoredCount,
    required this.failedCount,
  });

  /// The owner-facing "Recovery incomplete" condition: a pass that ran but
  /// did not fully restore. `unavailable`/`noBackup` are NOT incomplete —
  /// they have their own honest presentations.
  bool get isIncomplete =>
      status == RemoteKeychainRecoveryStatus.partiallyRestored ||
      status == RemoteKeychainRecoveryStatus.timedOut;

  String toJsonString() => jsonEncode({
    'status': status.name,
    'at': atUnix,
    'restored': restoredCount,
    'failed': failedCount,
  });

  /// Tolerant reader: an unknown/corrupt record yields null (treated as "no
  /// recorded outcome") rather than ever throwing into a settings screen.
  static RemoteRecoveryOutcome? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final statusName = decoded['status'];
      final at = decoded['at'];
      if (statusName is! String || at is! int) return null;
      final status = RemoteKeychainRecoveryStatus.values
          .where((value) => value.name == statusName)
          .firstOrNull;
      if (status == null) return null;
      return RemoteRecoveryOutcome(
        status: status,
        atUnix: at,
        restoredCount: switch (decoded['restored']) {
          final int count => count,
          _ => 0,
        },
        failedCount: switch (decoded['failed']) {
          final int count => count,
          _ => 0,
        },
      );
    } on FormatException {
      return null;
    }
  }
}
