import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletMetadataRelayRepository {
  @useResult
  Future<Result<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure>>
  publishAndVerify({
    required WalletMetadataEncryptedSnapshot snapshot,
    required List<WalletMetadataRelayUrl> relayUrls,
  });
}
