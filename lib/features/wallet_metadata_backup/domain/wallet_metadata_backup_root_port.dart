import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_root.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletMetadataBackupRootPort {
  @useResult
  Future<Result<WalletMetadataBackupRoot, WalletMetadataBackupFailure>>
  deriveLocalRoot();
}
