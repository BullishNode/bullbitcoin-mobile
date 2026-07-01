import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_keychain_manifest_nostr_encrypted_content_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

class BuildSignedKeychainManifestNostrEventUsecase {
  final BuildKeychainManifestNostrEncryptedContentUsecase buildEncryptedContent;
  final NostrIdentityFacade nostrIdentity;

  const BuildSignedKeychainManifestNostrEventUsecase({
    required this.buildEncryptedContent,
    required this.nostrIdentity,
  });

  Future<KeychainManifestNostrSignedEvent> execute({
    required String parentFingerprint,
    required String xprvBase58,
    bool allowEmpty = false,
    DateTime? now,
  }) async {
    try {
      final effectiveNow = now ?? DateTime.now().toUtc();
      final timestamp = effectiveNow.millisecondsSinceEpoch ~/ 1000;
      final authorPublicKeyHex = nostrIdentity
          .deriveWalletManifestPublicKeyFromXprv(xprvBase58);
      final encrypted = await buildEncryptedContent.execute(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprvBase58,
        allowEmpty: allowEmpty,
        now: effectiveNow,
      );
      final draft = KeychainManifestNostrEventDraft(
        authorPublicKeyHex: authorPublicKeyHex,
        encryptedContent: encrypted,
        createdAt: timestamp,
      );
      final eventId = keychainManifestNostrEventIdForDraft(draft);
      final signatureHex = nostrIdentity.signWalletManifestHashFromXprv(
        xprvBase58: xprvBase58,
        messageHashHex: eventId,
      );
      return KeychainManifestNostrSignedEvent.fromDraft(
        draft: draft,
        signatureHex: signatureHex,
      );
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestNostrSigningException(
        'failed to build signed keychain manifest Nostr event',
        cause: e,
      );
    }
  }
}
