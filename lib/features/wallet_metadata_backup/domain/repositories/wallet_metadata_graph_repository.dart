import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:meta/meta.dart';

abstract interface class WalletMetadataGraphRepository {
  @useResult
  Future<Result<WalletMetadataGraphScan, WalletMetadataBackupFailure>> fetch({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  });
}
