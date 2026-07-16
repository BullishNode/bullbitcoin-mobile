import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletMetadataSafeHeadRepository {
  @useResult
  Future<Result<WalletMetadataSafeHeadResult, WalletMetadataBackupFailure>>
  fetchForPublication({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  });
}
