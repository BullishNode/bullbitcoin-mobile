import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';

class NostrIdentityFacade {
  final DeriveNostrIdentityHandleUsecase _deriveHandle;

  const NostrIdentityFacade(this._deriveHandle);

  String deriveWalletBackupPublicKeyFromXprv(String xprvBase58) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletBackup,
    );
    return handle.publicKeyHex;
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

  String signWalletBackupHashFromXprv({
    required String xprvBase58,
    required String messageHashHex,
  }) {
    final handle = _deriveHandle.execute(
      xprvBase58: xprvBase58,
      role: NostrIdentityRole.walletBackup,
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
