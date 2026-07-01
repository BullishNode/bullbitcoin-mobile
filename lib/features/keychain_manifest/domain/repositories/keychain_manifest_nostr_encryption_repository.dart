import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';

abstract interface class KeychainManifestNostrEncryptionRepository {
  String encryptSnapshot({
    required KeychainManifestNostrSnapshot snapshot,
    required KeychainManifestNostrEncryptionKey key,
  });

  KeychainManifestNostrSnapshot decryptSnapshot({
    required String encryptedPayload,
    required KeychainManifestNostrEncryptionKey key,
  });
}
