import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_encryption_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_encryption_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
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
  String encryptSnapshot({
    required KeychainManifestNostrSnapshot snapshot,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    final encryptedContent = encryptionDatasource.encrypt(
      plaintext: snapshotCodec.encode(snapshot),
      key: key,
    );
    return KeychainManifestNostrEncryptedContentModel.fromEntity(
      KeychainManifestNostrEncryptedContent(encryptedContent: encryptedContent),
    ).toJsonString();
  }
}
