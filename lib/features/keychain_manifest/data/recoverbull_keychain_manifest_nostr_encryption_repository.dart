import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_encryption_model.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';

class RecoverBullKeychainManifestNostrEncryptionRepository
    implements KeychainManifestNostrEncryptionRepository {
  final KeychainManifestNostrSnapshotCodec snapshotCodec;
  final KeychainManifestNostrEncryptionCodec encryptionCodec;

  const RecoverBullKeychainManifestNostrEncryptionRepository({
    this.snapshotCodec = const KeychainManifestNostrSnapshotCodec(),
    this.encryptionCodec = const KeychainManifestNostrEncryptionCodec(),
  });

  @override
  String encryptSnapshot({
    required KeychainManifestNostrSnapshot snapshot,
    required KeychainManifestNostrEncryptionKey key,
  }) {
    return encryptionCodec.encrypt(
      plaintext: snapshotCodec.encode(snapshot),
      key: key,
    );
  }
}
