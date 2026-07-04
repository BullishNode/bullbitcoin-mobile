import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';

abstract interface class KeychainManifestNostrEncryptionRepository {
  KeychainManifestNostrCiphertext encryptSnapshot({
    required KeychainManifestNostrSnapshot snapshot,
    required KeychainManifestNostrEncryptionKey key,
  });

  KeychainManifestNostrSnapshot decryptSnapshot({
    required KeychainManifestNostrCiphertext ciphertext,
    required KeychainManifestNostrEncryptionKey key,
  });
}
