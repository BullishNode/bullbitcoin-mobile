import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class WalletManifestNostrHandleContext {
  final NostrKeychainHandle handle;
  final String rootFingerprint;

  const WalletManifestNostrHandleContext({
    required this.handle,
    required this.rootFingerprint,
  });
}

class DeriveWalletManifestNostrHandleUsecase {
  final DeriveWalletManifestRootKeyUsecase _deriveRootKey;

  const DeriveWalletManifestNostrHandleUsecase({
    required DeriveWalletManifestRootKeyUsecase deriveRootKey,
  }) : _deriveRootKey = deriveRootKey;

  Future<WalletManifestNostrHandleContext> execute() async {
    try {
      final rootKey = await _deriveRootKey.execute();
      return WalletManifestNostrHandleContext(
        handle: deriveWalletManifestHandleFromXprv(rootKey.xprvBase58),
        rootFingerprint: rootKey.rootFingerprint,
      );
    } on WalletManifestKeyDerivationException {
      rethrow;
    } catch (e) {
      throw WalletManifestKeyDerivationException(e);
    }
  }
}
