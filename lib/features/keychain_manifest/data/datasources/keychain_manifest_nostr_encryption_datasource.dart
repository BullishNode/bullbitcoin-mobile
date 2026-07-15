import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:hex/hex.dart';
import 'package:recoverbull/recoverbull.dart';

class KeychainManifestNostrEncryptionDatasource {
  const KeychainManifestNostrEncryptionDatasource();

  /// Encrypts [plaintext] under [key] and returns the bare
  /// `base64(nonce16 ‖ AES-256-CBC ciphertext ‖ HMAC-SHA256 32)` blob.
  ///
  /// `RecoverBull.createBackup` encrypts under the raw key and exposes exactly
  /// that merged byte layout as `ciphertext`; the surrounding `BullBackup`
  /// envelope (random id, salt, millisecond clock) is deliberately discarded so
  /// the published event content carries no cleartext markers and cannot be
  /// classified as a recoverbull backup.
  String encrypt({
    required String plaintext,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final backup = RecoverBull.createBackup(
        secret: utf8.encode(plaintext),
        backupKey: HEX.decode(key.hex),
      );
      return base64.encode(backup.ciphertext);
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to encrypt manifest content',
        cause: e,
      );
    }
  }

  /// Decrypts a bare `base64(nonce16 ‖ ciphertext ‖ HMAC-SHA256 32)` blob.
  ///
  /// The blob is the same merged layout `RecoverBull.restoreBackup` consumes as
  /// `BullBackup.ciphertext`; the envelope's other fields are unused for
  /// decryption, so they are reconstructed as empty placeholders. A wrong key,
  /// a flipped ciphertext byte, or a flipped HMAC byte fails authentication.
  String decrypt({
    required String base64Ciphertext,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final plaintext = RecoverBull.restoreBackup(
        backup: BullBackup(
          createdAt: 0,
          id: const [],
          ciphertext: base64.decode(base64Ciphertext),
          salt: const [],
        ),
        backupKey: HEX.decode(key.hex),
      );
      return utf8.decode(plaintext);
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to decrypt manifest content',
        cause: e,
      );
    }
  }
}
