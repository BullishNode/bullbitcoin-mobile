import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_file_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_entry.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_encryption.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_nostr_import.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_encryption_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/derive_keychain_manifest_nostr_encryption_key_usecase.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/parse_keychain_manifest_file_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';

class FetchKeychainManifestNostrImportPlanUsecase {
  static const _manifestFileCodec = KeychainManifestFileCodec();

  final KeychainManifestNostrRelayRepository relayRepository;
  final KeychainManifestNostrEncryptionRepository encryptionRepository;
  final ParseKeychainManifestFileUsecase parseManifestFile;
  final DeriveKeychainManifestNostrEncryptionKeyUsecase deriveEncryptionKey;
  final NostrIdentityFacade nostrIdentity;

  const FetchKeychainManifestNostrImportPlanUsecase({
    required this.relayRepository,
    required this.encryptionRepository,
    required this.parseManifestFile,
    required this.nostrIdentity,
    this.deriveEncryptionKey =
        const DeriveKeychainManifestNostrEncryptionKeyUsecase(),
  });

  Future<KeychainManifestNostrImportResult> execute({
    required String parentFingerprint,
    required String xprvBase58,
    required List<String> relayUrls,
  }) async {
    try {
      final normalizedParentFingerprint = KeychainManifestFingerprint.normalize(
        parentFingerprint,
      );
      final normalizedRelayUrls = relayUrls
          .map(KeychainManifestNostrRelayUrl.new)
          .toList(growable: false);
      if (normalizedRelayUrls.isEmpty) {
        throw KeychainManifestInvalidEntryException(
          'at least one keychain manifest Nostr relay URL is required',
        );
      }
      final authorPublicKeyHex = nostrIdentity
          .deriveWalletManifestPublicKeyFromXprv(xprvBase58);
      final fetchResult = await relayRepository.fetchManifestEvents(
        authorPublicKeyHex: authorPublicKeyHex,
        relayUrls: normalizedRelayUrls,
      );
      if (!fetchResult.contactedAnyRelay) {
        return const KeychainManifestNostrImportResult.relaysUnavailable();
      }
      if (fetchResult.events.isEmpty) {
        return const KeychainManifestNostrImportResult.noManifestFound();
      }
      final encryptionKey = deriveEncryptionKey.execute(
        xprvBase58: xprvBase58,
        expectedParentFingerprint: normalizedParentFingerprint,
      );
      final newestEvent = fetchResult.events.first;
      for (var index = 0; index < fetchResult.events.length; index++) {
        final event = fetchResult.events[index];
        final importPlan = _tryBuildImportPlan(
          event: event,
          encryptionKey: encryptionKey,
          expectedParentFingerprint: normalizedParentFingerprint,
        );
        if (importPlan == null) continue;
        if (index == 0) {
          return KeychainManifestNostrImportResult.latestRecoverable(
            importPlan: importPlan,
            eventCreatedAt: event.createdAt,
          );
        }
        return KeychainManifestNostrImportResult.newestFailedOlderRecoverable(
          importPlan: importPlan,
          selectedEventCreatedAt: event.createdAt,
          newestEventCreatedAt: newestEvent.createdAt,
        );
      }
      return const KeychainManifestNostrImportResult.noRecoverableManifest();
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestGenericException(cause: e);
    }
  }

  KeychainManifestImportPlan? _tryBuildImportPlan({
    required KeychainManifestNostrSignedEvent event,
    required KeychainManifestNostrEncryptionKey encryptionKey,
    required String expectedParentFingerprint,
  }) {
    try {
      final snapshot = encryptionRepository.decryptSnapshot(
        encryptedPayload: event.encryptedContent,
        key: encryptionKey,
      );
      if (snapshot.manifestFile.parentFingerprint !=
          expectedParentFingerprint) {
        return null;
      }
      return parseManifestFile.execute(
        _manifestFileCodec.encode(snapshot.manifestFile),
        expectedParentFingerprint: expectedParentFingerprint,
        allowEmpty: true,
      );
    } catch (_) {
      return null;
    }
  }
}
