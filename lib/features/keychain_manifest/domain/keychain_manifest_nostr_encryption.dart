import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:hex/hex.dart';

const int keychainManifestEncryptionBip85Application = 1642;
const String keychainManifestEncryptionBip85Path = "1642'/0'/1'";
const String keychainManifestEncryptionContentType =
    'bullbitcoin.keychain_manifest.encrypted.v1';

final class KeychainManifestNostrEncryptionException implements Exception {
  final String message;
  final Object? cause;

  const KeychainManifestNostrEncryptionException(this.message, {this.cause});

  @override
  String toString() => 'KeychainManifestNostrEncryptionException: $message';
}

final class KeychainManifestNostrEncryptionKey {
  static final _hex32Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

  final String hex;

  KeychainManifestNostrEncryptionKey(String hex)
    : hex = hex.trim().toLowerCase() {
    if (!_hex32Pattern.hasMatch(this.hex)) {
      throw const KeychainManifestNostrEncryptionException(
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
      throw const KeychainManifestNostrEncryptionException(
        'unsupported manifest encryption content version',
      );
    }
    if (contentType != keychainManifestEncryptionContentType) {
      throw const KeychainManifestNostrEncryptionException(
        'unsupported manifest encryption content type',
      );
    }
    if (encryptedContent.trim().isEmpty) {
      throw const KeychainManifestNostrEncryptionException(
        'encrypted manifest content is required',
      );
    }
  }
}

class DeriveKeychainManifestNostrEncryptionKeyUsecase {
  const DeriveKeychainManifestNostrEncryptionKeyUsecase();

  KeychainManifestNostrEncryptionKey execute({required String xprvBase58}) {
    try {
      final derivation = Bip85Entropy.derive(
        xprvBase58: xprvBase58,
        application: CustomApplication.fromNumber(
          keychainManifestEncryptionBip85Application,
        ),
        path: "0'/1'",
      );
      return KeychainManifestNostrEncryptionKey(
        HEX.encode(derivation.sublist(0, 32)),
      );
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to derive manifest encryption key',
        cause: e,
      );
    }
  }
}
