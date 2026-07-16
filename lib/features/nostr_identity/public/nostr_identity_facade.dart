import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';

final class WalletMetadataNostrSigner {
  final NostrKeychainHandle _handle;

  const WalletMetadataNostrSigner._(this._handle);

  String get publicKeyHex => _handle.publicKeyHex;

  String signHashHex(String messageHashHex) {
    return _handle.signHashHex(messageHashHex);
  }

  @override
  String toString() => 'WalletMetadataNostrSigner(publicKeyHex: $publicKeyHex)';
}

class NostrIdentityFacade {
  final DeriveNostrIdentityHandleUsecase _deriveHandle;

  const NostrIdentityFacade({required this._deriveHandle});

  String deriveWalletManifestPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletManifest,
    );
    return handle.publicKeyHex;
  }

  String deriveWalletMetadataPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletMetadata,
    );
    return handle.publicKeyHex;
  }

  WalletMetadataNostrSigner deriveWalletMetadataSignerFromXprv(
    String xprvBase58,
  ) {
    return WalletMetadataNostrSigner._(
      _deriveHandle.execute(
        xprvBase58: xprvBase58,
        role: NostrIdentityRole.walletMetadata,
      ),
    );
  }

  String deriveBullnymServerAuthPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymServerAuth,
    );
    return handle.publicKeyHex;
  }

  String deriveBullnymNip05VerificationPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymNip05Verification,
    );
    return handle.publicKeyHex;
  }

  String signWalletManifestHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletManifest,
    );
    return handle.signHashHex(messageHashHex);
  }

  String signBullnymServerAuthHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.bullnymServerAuth,
    );
    return handle.signHashHex(messageHashHex);
  }
}
