import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

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
