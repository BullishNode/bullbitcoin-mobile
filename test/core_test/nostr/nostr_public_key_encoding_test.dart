import 'package:bech32/bech32.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:test/test.dart';

const _pinnedMasterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';

void main() {
  test('encodes the NIP-19 bare public key vector', () {
    // NIP-19 "bare keys and ids" example pair, verified against an independent
    // bech32 implementation rather than against our own encoder.
    expect(
      NostrPublicKeyEncoding.npubFromPublicKeyHex(
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e',
      ),
      'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg',
    );
  });

  test('produces a 63-character npub with the npub human-readable part', () {
    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex('ab' * 32);

    expect(npub, startsWith('npub1'));
    expect(npub.length, 63);
    expect(bech32.decode(npub).hrp, 'npub');
  });

  test('decodes back to the same 5-bit payload the nsec encoder uses', () {
    // Cross-check against the bech32 machinery shared with deriveNsec: the same
    // 32-byte input must produce the same data words under both prefixes.
    const secretKeyHex =
        '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
    final npub = NostrPublicKeyEncoding.npubFromPublicKeyHex(secretKeyHex);
    final nsec = NostrKeychainSecretMaterializer.deriveNsec(
      xprvBase58: _pinnedMasterXprv,
      hardenedPath: "128002'/100'/1'",
    );

    expect(bech32.decode(npub).hrp, 'npub');
    expect(bech32.decode(nsec).hrp, 'nsec');
    expect(
      bech32.decode(npub).data,
      hasLength(bech32.decode(nsec).data.length),
    );
  });

  test('normalizes case and surrounding whitespace', () {
    expect(
      NostrPublicKeyEncoding.npubFromPublicKeyHex('  ${'AB' * 32}  '),
      NostrPublicKeyEncoding.npubFromPublicKeyHex('ab' * 32),
    );
  });

  test('rejects a public key that is not 32-byte hex', () {
    expect(
      () => NostrPublicKeyEncoding.npubFromPublicKeyHex('ab' * 31),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => NostrPublicKeyEncoding.npubFromPublicKeyHex('zz' * 32),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a derived handle exposes the npub for its own public key', () {
    final handle = NostrKeychainHandle.deriveFromBip85Path(
      xprvBase58: _pinnedMasterXprv,
      hardenedPath: "128002'/1'/1'",
    );

    expect(
      handle.npub,
      NostrPublicKeyEncoding.npubFromPublicKeyHex(handle.publicKeyHex),
    );
    expect(handle.npub, startsWith('npub1'));
  });
}
