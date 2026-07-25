import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'package:flutter_test/flutter_test.dart';

const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _messageHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _walletManifestPublicKey =
    '2dd5669c9e9dff487b377a12e2e9dda0a18861dcd85cd100c27aae5cd6a6b304';

void main() {
  const deriveHandle = DeriveNostrIdentityHandleUsecase(Bip85RegistryFacade());
  const facade = NostrIdentityFacade(deriveHandle);

  test('derives the unified wallet-backup public key', () {
    expect(
      facade.deriveWalletBackupPublicKeyFromXprv(_masterXprv),
      _walletManifestPublicKey,
    );
  });

  test('signs wallet-backup hashes under the unified backup role', () {
    final signature = facade.signWalletBackupHashFromXprv(
      xprvBase58: _masterXprv,
      messageHashHex: _messageHash,
    );

    expect(signature, hasLength(128));
    expect(
      bip340.verify(_walletManifestPublicKey, _messageHash, signature),
      isTrue,
    );
  });
}
