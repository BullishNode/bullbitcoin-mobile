import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';

abstract class WalletManifestNostrSnapshotStore {
  Future<void> publish({
    required NostrKeychainHandle handle,
    required WalletManifestSnapshot snapshot,
  });

  Future<WalletManifestSnapshot?> fetchLatest({
    required NostrKeychainHandle handle,
  });
}
