import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:hex/hex.dart';
import 'package:recoverbull/recoverbull.dart';

class KeychainManifestNostrEncryptionCodec {
  const KeychainManifestNostrEncryptionCodec();

  String encrypt({
    required String plaintext,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final backup = RecoverBull.createBackup(
        secret: utf8.encode(plaintext),
        backupKey: HEX.decode(key.hex),
      );
      return jsonEncode({
        'version': 1,
        'contentType': keychainManifestEncryptionContentType,
        'encryptedContent': backup.toJson(),
      });
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to encrypt manifest content',
        cause: e,
      );
    }
  }

  String decrypt({
    required String payload,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) {
        throw const KeychainManifestNostrEncryptionException(
          'encrypted manifest payload must be a JSON object',
        );
      }
      final encrypted = KeychainManifestNostrEncryptedContent(
        version: _int(decoded, 'version'),
        contentType: _string(decoded, 'contentType'),
        encryptedContent: _string(decoded, 'encryptedContent'),
      );
      final backup = BullBackup.fromJson(encrypted.encryptedContent);
      final plaintext = RecoverBull.restoreBackup(
        backup: backup,
        backupKey: HEX.decode(key.hex),
      );
      return utf8.decode(plaintext);
    } on KeychainManifestNostrEncryptionException {
      rethrow;
    } on FormatException catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'encrypted manifest payload is malformed',
        cause: e,
      );
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to decrypt manifest content',
        cause: e,
      );
    }
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw KeychainManifestNostrEncryptionException(
    'encrypted manifest payload field $key must be a string',
  );
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw KeychainManifestNostrEncryptionException(
    'encrypted manifest payload field $key must be an integer',
  );
}
