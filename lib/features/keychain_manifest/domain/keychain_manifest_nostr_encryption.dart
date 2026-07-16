import 'package:bb_mobile/core/nostr/nostr_authenticated_cipher.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

final class KeychainManifestNostrEncryptionKey {
  final String hex;

  const KeychainManifestNostrEncryptionKey._(this.hex);

  factory KeychainManifestNostrEncryptionKey(String hex) {
    final normalized = hex.trim().toLowerCase();
    try {
      NostrAuthenticatedCipherKey(normalized);
      return KeychainManifestNostrEncryptionKey._(normalized);
    } on NostrAuthenticatedCipherException catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption key must be a 32-byte hex value',
        cause: e,
      );
    }
  }
}
