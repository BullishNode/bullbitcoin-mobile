import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_key_deriver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const deriver = WalletMetadataKeyDeriver();

  test('freezes the metadata encryption key', () {
    final key = deriver.deriveEncryptionKey(
      xprvBase58: _masterXprv,
      expectedParentFingerprint: _parentFingerprint,
    );

    expect(
      key.hex,
      'b101cd2144474286c3221c35b96b431c7c80a75a4d813a63131c1f545d5ea01d',
    );
    expect(key.toString(), isNot(contains(key.hex)));
  });

  test('rejects a parent mismatch before deriving metadata material', () {
    expect(
      () => deriver.deriveEncryptionKey(
        xprvBase58: _masterXprv,
        expectedParentFingerprint: 'ffffffff',
      ),
      throwsA(isA<WalletMetadataKeyDerivationException>()),
    );
  });

  test('maps a malformed xprv to a key derivation exception', () {
    expect(
      () => deriver.deriveEncryptionKey(
        xprvBase58: 'not-an-xprv',
        expectedParentFingerprint: _parentFingerprint,
      ),
      throwsA(isA<WalletMetadataKeyDerivationException>()),
    );
  });
}

const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '627ef3a6';
