import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:hex/hex.dart';
import 'package:recoverbull/recoverbull.dart';

class KeychainManifestNostrEncryptionDatasource {
  const KeychainManifestNostrEncryptionDatasource();

  String encrypt({
    required String plaintext,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final backup = RecoverBull.createBackup(
        secret: utf8.encode(plaintext),
        backupKey: HEX.decode(key.hex),
      );
      return backup.toJson();
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to encrypt manifest content',
        cause: e,
      );
    }
  }
}
