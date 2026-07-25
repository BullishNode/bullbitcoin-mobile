import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

/// Master BIP32 root key from the official BIP85 test vectors.
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';

void main() {
  const usecase = DeriveNostrIdentityHandleUsecase(Bip85RegistryFacade());

  test('derives role keys from the registry key reservations', () {
    final walletBackupHandle = usecase.execute(
      xprvBase58: _masterXprv,
      role: NostrIdentityRole.walletBackup,
    );
    final bullnymAuthHandle = usecase.execute(
      xprvBase58: _masterXprv,
      role: NostrIdentityRole.bullnymServerAuth,
    );
    final bullnymVerificationHandle = usecase.execute(
      xprvBase58: _masterXprv,
      role: NostrIdentityRole.bullnymNip05Verification,
    );

    expect(
      walletBackupHandle.publicKeyHex,
      NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: _masterXprv,
        hardenedPath: "128002'/100'/1'",
      ).publicKeyHex,
    );
    expect(
      bullnymAuthHandle.publicKeyHex,
      NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: _masterXprv,
        hardenedPath: "128002'/101'/1'",
      ).publicKeyHex,
    );
    expect(
      bullnymVerificationHandle.publicKeyHex,
      NostrKeychainHandle.deriveFromBip85Path(
        xprvBase58: _masterXprv,
        hardenedPath: "128002'/102'/1'",
      ).publicKeyHex,
    );
    expect(
      walletBackupHandle.publicKeyHex,
      isNot(bullnymAuthHandle.publicKeyHex),
    );
    expect(
      bullnymAuthHandle.publicKeyHex,
      isNot(bullnymVerificationHandle.publicKeyHex),
    );
  });

  test('derives valid distinct role keys', () {
    final roleKeys = NostrIdentityRole.values
        .map(
          (role) =>
              usecase.execute(xprvBase58: _masterXprv, role: role).publicKeyHex,
        )
        .toSet();

    expect(roleKeys, hasLength(NostrIdentityRole.values.length));
    for (final key in roleKeys) {
      expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
    }
  });
}
