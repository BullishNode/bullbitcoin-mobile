import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

const String keychainManifestEncryptionContentType =
    'bullbitcoin.keychain_manifest.encrypted.v1';

final class KeychainManifestNostrEncryptionKey {
  static final _hex32Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final String hex;

  KeychainManifestNostrEncryptionKey(String hex)
    : hex = hex.trim().toLowerCase() {
    if (!_hex32Pattern.hasMatch(this.hex)) {
      throw KeychainManifestNostrEncryptionException(
        'manifest encryption key must be a 32-byte hex value',
      );
    }
  }
}

final class KeychainManifestNostrEncryptedContent {
  final int version;
  final String contentType;
  final String encryptedContent;

  KeychainManifestNostrEncryptedContent({
    this.version = 1,
    this.contentType = keychainManifestEncryptionContentType,
    required this.encryptedContent,
  }) {
    if (version != 1) {
      throw KeychainManifestNostrEncryptionException(
        'unsupported manifest encryption content version',
      );
    }
    if (contentType != keychainManifestEncryptionContentType) {
      throw KeychainManifestNostrEncryptionException(
        'unsupported manifest encryption content type',
      );
    }
    if (encryptedContent.trim().isEmpty) {
      throw KeychainManifestNostrEncryptionException(
        'encrypted manifest content is required',
      );
    }
  }
}
