import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';

final RegExp _safeHeadEventIdPattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _safeHeadContentHashPattern = RegExp(r'^[0-9a-f]{64}$');

final class WalletMetadataRemoteHead {
  final String rootEventId;
  final int rootEventCreatedAt;
  final int highestObservedRootCreatedAt;
  final String canonicalContentHash;
  final WalletMetadataSnapshotRoot root;
  final List<WalletMetadataRecord> records;

  WalletMetadataRemoteHead({
    required this.rootEventId,
    required this.rootEventCreatedAt,
    required this.highestObservedRootCreatedAt,
    required this.canonicalContentHash,
    required this.root,
    required List<WalletMetadataRecord> records,
  }) : records = List.unmodifiable(records) {
    if (!_safeHeadEventIdPattern.hasMatch(rootEventId)) {
      throw ArgumentError.value(rootEventId, 'rootEventId');
    }
    if (!_safeHeadContentHashPattern.hasMatch(canonicalContentHash)) {
      throw ArgumentError.value(canonicalContentHash, 'canonicalContentHash');
    }
    if (rootEventCreatedAt < 0 ||
        highestObservedRootCreatedAt < rootEventCreatedAt ||
        highestObservedRootCreatedAt >
            WalletMetadataBackupLimits.maxSignedInt64) {
      throw ArgumentError('wallet metadata remote head timestamps are invalid');
    }
    if (this.records.length != root.recordCount) {
      throw ArgumentError.value(
        records,
        'records',
        'does not match root count',
      );
    }
  }
}

sealed class WalletMetadataSafeHeadResult {
  const WalletMetadataSafeHeadResult();
}

final class WalletMetadataSafeHeadNoSnapshot
    extends WalletMetadataSafeHeadResult {
  const WalletMetadataSafeHeadNoSnapshot();
}

final class WalletMetadataSafeHeadCompatible
    extends WalletMetadataSafeHeadResult {
  final WalletMetadataRemoteHead head;

  const WalletMetadataSafeHeadCompatible(this.head);
}

final class WalletMetadataSafeHeadUnsupported
    extends WalletMetadataSafeHeadResult {
  final WalletMetadataBackupUnsupportedEnvelope unsupported;

  const WalletMetadataSafeHeadUnsupported(this.unsupported);
}

final class WalletMetadataSafeHeadIncomplete
    extends WalletMetadataSafeHeadResult {
  const WalletMetadataSafeHeadIncomplete();
}

final class WalletMetadataSafeHeadUnavailable
    extends WalletMetadataSafeHeadResult {
  const WalletMetadataSafeHeadUnavailable();
}
