import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_nostr_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/build_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class PublishLocalWalletManifestUsecase {
  final BuildWalletManifestSnapshotUsecase _buildSnapshot;
  final DeriveWalletManifestNostrHandleUsecase _deriveHandle;
  final WalletManifestNostrSnapshotStore _nostrSnapshotStore;

  const PublishLocalWalletManifestUsecase({
    required BuildWalletManifestSnapshotUsecase buildSnapshot,
    required DeriveWalletManifestNostrHandleUsecase deriveHandle,
    required WalletManifestNostrSnapshotStore nostrSnapshotStore,
  }) : _buildSnapshot = buildSnapshot,
       _deriveHandle = deriveHandle,
       _nostrSnapshotStore = nostrSnapshotStore;

  Future<int> execute() async {
    final context = await _safeDeriveHandle();
    final localSnapshot = await _buildSnapshot.execute(
      rootFingerprint: context.rootFingerprint,
    );
    final snapshot = await _snapshotPreservingRemoteAccounts(
      handleContext: context,
      localSnapshot: localSnapshot,
    );
    await _nostrSnapshotStore.publish(
      handle: context.handle,
      snapshot: snapshot,
    );
    return snapshot.accounts.length;
  }

  Future<WalletManifestSnapshot> _snapshotPreservingRemoteAccounts({
    required WalletManifestNostrHandleContext handleContext,
    required WalletManifestSnapshot localSnapshot,
  }) async {
    try {
      final remoteSnapshot = await _nostrSnapshotStore.fetchLatest(
        handle: handleContext.handle,
      );
      if (remoteSnapshot == null || remoteSnapshot.accounts.isEmpty) {
        return localSnapshot;
      }
      return WalletManifestSnapshot(
        createdAt: localSnapshot.createdAt,
        accounts: [...remoteSnapshot.accounts, ...localSnapshot.accounts],
      ).collapseDuplicates();
    } on WalletManifestException {
      rethrow;
    } catch (e) {
      throw WalletManifestSnapshotPublishException(e);
    }
  }

  Future<WalletManifestNostrHandleContext> _safeDeriveHandle() async {
    try {
      return await _deriveHandle.execute();
    } on WalletManifestKeyDerivationException catch (e) {
      throw WalletManifestSnapshotPublishException(e);
    } catch (_) {
      throw WalletManifestSnapshotPublishException(
        'wallet manifest key derivation failed',
      );
    }
  }
}
