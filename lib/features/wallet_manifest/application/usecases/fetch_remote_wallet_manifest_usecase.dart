import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_nostr_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class FetchRemoteWalletManifestUsecase {
  final DeriveWalletManifestNostrHandleUsecase _deriveHandle;
  final WalletManifestNostrSnapshotStore _nostrSnapshotStore;

  const FetchRemoteWalletManifestUsecase({
    required DeriveWalletManifestNostrHandleUsecase deriveHandle,
    required WalletManifestNostrSnapshotStore nostrSnapshotStore,
  }) : _deriveHandle = deriveHandle,
       _nostrSnapshotStore = nostrSnapshotStore;

  Future<WalletManifestSnapshot?> execute() async {
    final context = await _safeDeriveHandle();
    return _nostrSnapshotStore.fetchLatest(handle: context.handle);
  }

  Future<WalletManifestNostrHandleContext> _safeDeriveHandle() async {
    try {
      return await _deriveHandle.execute();
    } on WalletManifestKeyDerivationException catch (e) {
      throw WalletManifestSnapshotFetchException(e);
    } catch (_) {
      throw WalletManifestSnapshotFetchException(
        'wallet manifest key derivation failed',
      );
    }
  }
}
