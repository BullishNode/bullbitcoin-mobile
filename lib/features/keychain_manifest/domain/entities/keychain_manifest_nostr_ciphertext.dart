import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

/// A structurally-validated Nostr manifest ciphertext payload.
///
/// The published Nostr manifest event content must be an encrypted blob, never
/// a plaintext snapshot. This value object is the only shape the event draft
/// accepts, so plaintext JSON snapshot output (which is not valid base64) or a
/// blob too short to hold a nonce, at least one cipher block, and a MAC is
/// rejected at construction (AD-5). Validation is pure `dart:convert`: it
/// proves the payload is base64 of a plausible ciphertext length, not that it
/// actually decrypts.
class KeychainManifestNostrCiphertext {
  /// 16-byte nonce + at least one 16-byte cipher block + 32-byte HMAC.
  static const int minimumByteLength = 64;

  final String value;

  const KeychainManifestNostrCiphertext._(this.value);

  factory KeychainManifestNostrCiphertext(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content is required',
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64.decode(trimmed);
    } on FormatException catch (e) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content must be base64-encoded ciphertext',
        cause: e,
      );
    }
    if (bytes.length < minimumByteLength) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content is too short to be a ciphertext',
      );
    }
    return KeychainManifestNostrCiphertext._(trimmed);
  }
}
