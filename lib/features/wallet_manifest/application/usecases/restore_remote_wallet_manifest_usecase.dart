import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';

class RestoreRemoteWalletManifestUsecase {
  final FetchRemoteWalletManifestUsecase _fetchRemoteManifest;
  final RestoreWalletManifestSnapshotUsecase _restoreSnapshot;

  const RestoreRemoteWalletManifestUsecase({
    required FetchRemoteWalletManifestUsecase fetchRemoteManifest,
    required RestoreWalletManifestSnapshotUsecase restoreSnapshot,
  }) : _fetchRemoteManifest = fetchRemoteManifest,
       _restoreSnapshot = restoreSnapshot;

  Future<RestoreRemoteWalletManifestResult?> execute() async {
    final snapshot = await _fetchRemoteManifest.execute();
    if (snapshot == null) return null;

    final result = await _restoreSnapshot.execute(snapshot: snapshot);
    return RestoreRemoteWalletManifestResult(
      restoredCount: result.restored.length,
      alreadyPresentCount: result.alreadyPresent.length,
      skippedCount: result.skipped.length,
      failedCount: result.failed.length,
      walletStateMayHaveChanged:
          result.restored.isNotEmpty ||
          result.alreadyPresent.isNotEmpty ||
          result.failed.any((outcome) => outcome.walletId != null),
    );
  }
}

class RestoreRemoteWalletManifestResult {
  final int restoredCount;
  final int alreadyPresentCount;
  final int skippedCount;
  final int failedCount;
  final bool walletStateMayHaveChanged;

  const RestoreRemoteWalletManifestResult({
    required this.restoredCount,
    required this.alreadyPresentCount,
    required this.skippedCount,
    required this.failedCount,
    this.walletStateMayHaveChanged = false,
  });

  bool get complete => failedCount == 0 && skippedCount == 0;
}
