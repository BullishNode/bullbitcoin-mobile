import 'package:bb_mobile/core/nostr/nostr_identity.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/nostr_identity/domain/nostr_identity_role.dart';

export 'package:bb_mobile/features/nostr_identity/domain/nostr_identity_role.dart';

NostrKeychainHandle deriveNostrHandleForRoleFromXprv({
  required String xprvBase58,
  required NostrIdentityRole role,
}) {
  return NostrKeychainHandle.deriveFromBip85(
    xprvBase58: xprvBase58,
    identity: role.identity,
    account: role.account,
  );
}

NostrIdentity deriveNostrIdentityForRoleFromXprv({
  required String xprvBase58,
  required NostrIdentityRole role,
}) {
  return NostrIdentity.derive(
    xprvBase58: xprvBase58,
    identity: role.identity,
    account: role.account,
  );
}

NostrKeychainHandle deriveWalletManifestHandleFromXprv(String xprvBase58) {
  return deriveNostrHandleForRoleFromXprv(
    xprvBase58: xprvBase58,
    role: NostrIdentityRole.walletManifest,
  );
}

NostrKeychainHandle deriveBullnymServerAuthHandleFromXprv(String xprvBase58) {
  return deriveNostrHandleForRoleFromXprv(
    xprvBase58: xprvBase58,
    role: NostrIdentityRole.bullnymServerAuth,
  );
}

NostrIdentity deriveBullnymServerAuthIdentityFromXprv(String xprvBase58) {
  return deriveNostrIdentityForRoleFromXprv(
    xprvBase58: xprvBase58,
    role: NostrIdentityRole.bullnymServerAuth,
  );
}

NostrKeychainHandle deriveNip05VerificationHandleFromXprv(String xprvBase58) {
  return deriveNostrHandleForRoleFromXprv(
    xprvBase58: xprvBase58,
    role: NostrIdentityRole.nip05Verification,
  );
}
