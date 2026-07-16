import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cipher = RecoverBullNostrAuthenticatedCipher();
  final key = NostrAuthenticatedCipherKey(_keyHex);

  test('round trips a bare authenticated ciphertext', () {
    final encrypted = cipher.encrypt(
      plaintext: '{"private":"metadata"}',
      key: key,
    );

    expect(encrypted.value, isNot(contains('metadata')));
    expect(base64.decode(encrypted.value), hasLength(greaterThanOrEqualTo(64)));
    expect(
      cipher.decrypt(ciphertext: encrypted, key: key),
      '{"private":"metadata"}',
    );
  });

  test('rejects malformed keys and ciphertexts', () {
    expect(
      () => NostrAuthenticatedCipherKey('not-a-key'),
      throwsA(isA<NostrAuthenticatedCipherException>()),
    );
    expect(
      () => NostrAuthenticatedCiphertext('{"plaintext":true}'),
      throwsA(isA<NostrAuthenticatedCipherException>()),
    );
    expect(
      () => NostrAuthenticatedCiphertext(base64.encode(List.filled(32, 0))),
      throwsA(isA<NostrAuthenticatedCipherException>()),
    );
  });

  test('rejects tampering and the wrong key', () {
    final encrypted = cipher.encrypt(plaintext: 'secret', key: key);
    final tamperedBytes = base64.decode(encrypted.value);
    tamperedBytes[tamperedBytes.length - 1] ^= 0xff;
    final tampered = NostrAuthenticatedCiphertext(base64.encode(tamperedBytes));
    final wrongKey = NostrAuthenticatedCipherKey(
      'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100',
    );

    expect(
      () => cipher.decrypt(ciphertext: tampered, key: key),
      throwsA(isA<NostrAuthenticatedCipherException>()),
    );
    expect(
      () => cipher.decrypt(ciphertext: encrypted, key: wrongKey),
      throwsA(isA<NostrAuthenticatedCipherException>()),
    );
  });

  test('does not expose key material through toString', () {
    expect(key.toString(), isNot(contains(_keyHex)));
  });
}

const _keyHex =
    '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';
