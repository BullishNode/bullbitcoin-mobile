import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_file_usecase.dart';

class BuildKeychainManifestNostrEncryptedContentUsecase {
  final BuildKeychainManifestFileUsecase buildManifestFile;
  final DeriveKeychainManifestNostrEncryptionKeyUsecase deriveEncryptionKey;
  final KeychainManifestNostrEncryptionRepository encryptionRepository;

  const BuildKeychainManifestNostrEncryptedContentUsecase({
    required this.buildManifestFile,
    required this.encryptionRepository,
    this.deriveEncryptionKey =
        const DeriveKeychainManifestNostrEncryptionKeyUsecase(),
  });

  Future<KeychainManifestNostrEncryptedContent> execute({
    required String parentFingerprint,
    required String xprvBase58,
    bool allowEmpty = false,
    DateTime? now,
  }) async {
    try {
      final manifestFile = await buildManifestFile.execute(
        parentFingerprint,
        now: now,
      );
      if (manifestFile.entries.isEmpty && !allowEmpty) {
        throw KeychainManifestEmptyInventoryException();
      }
      final encryptionKey = deriveEncryptionKey.execute(xprvBase58: xprvBase58);
      final encryptedContent = encryptionRepository.encryptSnapshot(
        snapshot: KeychainManifestNostrSnapshot(manifestFile: manifestFile),
        key: encryptionKey,
      );
      return KeychainManifestNostrEncryptedContent(
        encryptedContent: encryptedContent,
      );
    } on KeychainManifestException {
      rethrow;
    } on KeychainManifestNostrEncryptionException {
      rethrow;
    } catch (e) {
      throw KeychainManifestNostrEncryptionException(
        'failed to build encrypted manifest content',
        cause: e,
      );
    }
  }
}
