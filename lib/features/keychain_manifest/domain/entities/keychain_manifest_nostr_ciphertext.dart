import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
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
  static const int minimumByteLength =
      NostrAuthenticatedCiphertext.minimumByteLength;

  final String value;

  const KeychainManifestNostrCiphertext._(this.value);

  factory KeychainManifestNostrCiphertext(String value) {
    try {
      final ciphertext = NostrAuthenticatedCiphertext(value);
      return KeychainManifestNostrCiphertext._(ciphertext.value);
    } on NostrAuthenticatedCipherException catch (e) {
      throw KeychainManifestNostrEventException(
        'encrypted Nostr event content must be a valid ciphertext',
        cause: e,
      );
    }
  }
}
