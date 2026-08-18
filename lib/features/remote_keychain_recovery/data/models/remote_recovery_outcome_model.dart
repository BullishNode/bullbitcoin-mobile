import 'dart:convert';

import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_recovery_outcome.dart';

final class RemoteRecoveryOutcomeModel {
  const RemoteRecoveryOutcomeModel({
    required this.status,
    required this.atUnix,
    required this.restoredCount,
    required this.failedCount,
  });

  final String status;
  final int atUnix;
  final int restoredCount;
  final int failedCount;

  factory RemoteRecoveryOutcomeModel.fromDomain(RemoteRecoveryOutcome value) {
    return RemoteRecoveryOutcomeModel(
      status: value.status.name,
      atUnix: value.atUnix,
      restoredCount: value.restoredCount,
      failedCount: value.failedCount,
    );
  }

  RemoteRecoveryOutcome? toDomain() {
    final parsedStatus = RemoteKeychainRecoveryStatus.values
        .where((value) => value.name == status)
        .firstOrNull;
    if (parsedStatus == null) return null;
    return RemoteRecoveryOutcome(
      status: parsedStatus,
      atUnix: atUnix,
      restoredCount: restoredCount,
      failedCount: failedCount,
    );
  }

  String encode() => jsonEncode({
    'status': status,
    'at': atUnix,
    'restored': restoredCount,
    'failed': failedCount,
  });

  /// Tolerant reader: an unknown/corrupt record yields null rather than
  /// throwing into the settings surface.
  static RemoteRecoveryOutcomeModel? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final status = decoded['status'];
      final at = decoded['at'];
      if (status is! String || at is! int) return null;
      return RemoteRecoveryOutcomeModel(
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
