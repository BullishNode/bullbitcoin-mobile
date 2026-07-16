import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;

const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _messageHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _walletManifestPublicKey =
    '1072ff1a657708c194dcd1fa57d894eab3e8fca1b65950cee5c05f35a4425b9f';
const _walletMetadataPublicKey =
    '21ee43d352f3506c8cef5ee18f028efec0a2f71c510638afd0f7869f630a7dfd';

void main() {
  const deriveHandle = DeriveNostrIdentityHandleUsecase(
    registry: Bip85RegistryFacade(),
  );
  const facade = NostrIdentityFacade(deriveHandle: deriveHandle);

  test('exposes purpose-separated manifest and metadata public keys', () {
    expect(
      facade.deriveWalletManifestPublicKeyFromXprv(_masterXprv),
      _walletManifestPublicKey,
    );
    expect(
      facade.deriveWalletMetadataPublicKeyFromXprv(_masterXprv),
      _walletMetadataPublicKey,
    );
    expect(_walletMetadataPublicKey, isNot(_walletManifestPublicKey));
  });

  test('signs metadata hashes only under the metadata role', () {
    final signature = facade
        .deriveWalletMetadataSignerFromXprv(_masterXprv)
        .signHashHex(_messageHash);

    expect(signature, hasLength(128));
    expect(
      nostr.Schnorr.verify(
        publicKey: _walletMetadataPublicKey,
        message: _messageHash,
        signature: signature,
      ),
      isTrue,
    );
    expect(
      nostr.Schnorr.verify(
        publicKey: _walletManifestPublicKey,
        message: _messageHash,
        signature: signature,
      ),
      isFalse,
    );
  });

  test('provides a short-lived metadata signer without exposing its key', () {
    final signer = facade.deriveWalletMetadataSignerFromXprv(_masterXprv);

    expect(signer.publicKeyHex, _walletMetadataPublicKey);
    expect(signer.signHashHex(_messageHash), hasLength(128));
    expect(signer.toString(), isNot(contains(_masterXprv)));
  });
}
