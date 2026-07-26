export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

class WalletMetadataBackupFacade {
  final WalletMetadataBackupSectionProvider _sectionProvider;

  const WalletMetadataBackupFacade(this._sectionProvider);

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recoverSection({
    required String payload,
    required Set<String> createdWalletRefs,
    DateTime? deadline,
  }) async => (await _sectionProvider.recoverSection(
    payload: payload,
    createdWalletRefs: createdWalletRefs,
    deadline: deadline,
  )).map(WalletMetadataRecoveryResult.applied);
}

enum WalletMetadataRecoveryStatus {
  recovered,
  partiallyRecovered,
  noSnapshotFound,
  remoteUnavailable,
  unsupportedNewerEnvelope,
}

final class WalletMetadataRecoveryResult {
  final WalletMetadataRecoveryStatus status;
  final WalletMetadataRecoveryApplyResult? applyResult;

  const WalletMetadataRecoveryResult._({
    required this.status,
    this.applyResult,
  });

  factory WalletMetadataRecoveryResult.applied(
    WalletMetadataRecoveryApplyResult result,
  ) => WalletMetadataRecoveryResult._(
    status: result.publicationBlocked
        ? WalletMetadataRecoveryStatus.partiallyRecovered
        : WalletMetadataRecoveryStatus.recovered,
    applyResult: result,
  );

  const WalletMetadataRecoveryResult.noSnapshotFound()
    : this._(status: WalletMetadataRecoveryStatus.noSnapshotFound);
}
