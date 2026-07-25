import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletMetadataRecoveryFence {
  void close();
}

/// The wallet-backup feature owns transport, encryption, state, and
/// publication. Metadata contributes only this section-level boundary.
abstract interface class WalletMetadataBackupSectionProvider {
  @useResult
  Future<Result<String?, WalletMetadataBackupFailure>> composeSection({
    required String parentFingerprint,
    required String? remotePayload,
  });

  @useResult
  Future<Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>>
  recoverSection({
    required String payload,
    required Set<String> createdWalletRefs,
  });

  Stream<void> get changes;

  Future<void> dispose();
}
