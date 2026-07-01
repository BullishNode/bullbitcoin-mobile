import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_encryption_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';

class RecoverBullKeychainManifestNostrEncryptionRepository
    implements KeychainManifestNostrEncryptionRepository {
  final KeychainManifestNostrSnapshotCodec snapshotCodec;
  final KeychainManifestNostrEncryptionDatasource encryptionDatasource;

  const RecoverBullKeychainManifestNostrEncryptionRepository({
    this.snapshotCodec = const KeychainManifestNostrSnapshotCodec(),
    this.encryptionDatasource =
        const KeychainManifestNostrEncryptionDatasource(),
  });

  @override
  KeychainManifestNostrCiphertext encryptSnapshot({
    required KeychainManifestNostrSnapshot snapshot,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    // Serialization happens exactly once, here at the encrypt boundary: the
    // snapshot JSON is encrypted and returned as an opaque ciphertext value
    // object. There is no cleartext wrapper, so nothing can double-wrap it.
    final blob = encryptionDatasource.encrypt(
      plaintext: snapshotCodec.encode(snapshot),
      key: key,
    );
    return KeychainManifestNostrCiphertext(blob);
  }

  @override
  KeychainManifestNostrSnapshot decryptSnapshot({
    required KeychainManifestNostrCiphertext ciphertext,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    final plaintext = encryptionDatasource.decrypt(
      base64Ciphertext: ciphertext.value,
      key: key,
    );
    return snapshotCodec.decode(plaintext);
  }

  @override
  KeychainManifestNostrSnapshot decryptSnapshot({
    required String encryptedPayload,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    try {
      final encryptedContent =
          KeychainManifestNostrEncryptedContentModel.fromJsonString(
            encryptedPayload,
          ).toEntity();
      final plaintext = encryptionDatasource.decrypt(
        encryptedContent: encryptedContent.encryptedContent,
        key: key,
      );
      return snapshotCodec.decode(plaintext);
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to decrypt manifest content',
        cause: e,
      );
    }
  }
}
