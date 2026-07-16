import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

final class BuildWalletMetadataSnapshotUsecase {
  final WalletMetadataSnapshotRepository _repository;

  const BuildWalletMetadataSnapshotUsecase(this._repository);

  @useResult
  Result<WalletMetadataEncryptedSnapshot, WalletMetadataBackupFailure> execute({
    required String xprvBase58,
    required String parentFingerprint,
    required int revision,
    required int createdAt,
    required List<WalletMetadataRecord> records,
    required List<WalletMetadataSection> sections,
  }) {
    return _repository.build(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
      revision: revision,
      createdAt: createdAt,
      records: records,
      sections: sections,
    );
  }
}
