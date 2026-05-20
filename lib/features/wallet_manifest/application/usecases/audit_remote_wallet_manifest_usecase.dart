import 'package:bb_mobile/features/wallet_manifest/application/usecases/build_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_remote_wallet_manifest_usecase.dart';

class AuditRemoteWalletManifestUsecase {
  final FetchRemoteWalletManifestUsecase fetchRemoteManifest;
  final BuildWalletManifestSnapshotUsecase buildLocalSnapshot;
  final DeriveWalletManifestRootKeyUsecase deriveRootKey;

  AuditRemoteWalletManifestUsecase({
    required this.fetchRemoteManifest,
    required this.buildLocalSnapshot,
    required this.deriveRootKey,
  });

  Future<AuditRemoteWalletManifestResult> execute() async {
    final rootKey = await deriveRootKey.execute();
    final localSnapshot = await buildLocalSnapshot.execute(
      rootFingerprint: rootKey.rootFingerprint,
    );
    final localIdentities = localSnapshot.accounts
        .map((account) => account.identity)
        .toSet();

    final remoteSnapshot = await fetchRemoteManifest.execute();
    if (remoteSnapshot == null) {
      return AuditRemoteWalletManifestResult(
        remoteManifestFound: false,
        matchingCount: 0,
        missingLocalCount: 0,
        missingRemoteCount: localIdentities.length,
      );
    }

    final remoteIdentities = remoteSnapshot.accounts
        .map((account) => account.identity)
        .toSet();

    final matchingCount = remoteIdentities.intersection(localIdentities).length;
    final missingLocalCount = remoteIdentities
        .difference(localIdentities)
        .length;
    final missingRemoteCount = localIdentities
        .difference(remoteIdentities)
        .length;

    return AuditRemoteWalletManifestResult(
      matchingCount: matchingCount,
      missingLocalCount: missingLocalCount,
      missingRemoteCount: missingRemoteCount,
    );
  }
}

class AuditRemoteWalletManifestResult {
  final bool remoteManifestFound;
  final int matchingCount;
  final int missingLocalCount;
  final int missingRemoteCount;

  const AuditRemoteWalletManifestResult({
    this.remoteManifestFound = true,
    required this.matchingCount,
    required this.missingLocalCount,
    required this.missingRemoteCount,
  });

  bool get matches =>
      remoteManifestFound && missingLocalCount == 0 && missingRemoteCount == 0;
}
