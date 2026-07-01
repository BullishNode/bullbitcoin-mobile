import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/usecases/build_signed_keychain_manifest_nostr_event_usecase.dart';

class PublishKeychainManifestNostrEventUsecase {
  final BuildSignedKeychainManifestNostrEventUsecase buildSignedEvent;
  final KeychainManifestNostrRelayRepository relayRepository;

  const PublishKeychainManifestNostrEventUsecase({
    required this.buildSignedEvent,
    required this.relayRepository,
  });

  Future<void> execute({
    required String parentFingerprint,
    required String xprvBase58,
    required List<String> relayUrls,
    DateTime? now,
  }) async {
    try {
      final normalizedRelayUrls = relayUrls
          .map(KeychainManifestNostrRelayUrl.new)
          .toList(growable: false);
      if (normalizedRelayUrls.isEmpty) {
        throw KeychainManifestInvalidEntryException(
          'at least one keychain manifest Nostr relay URL is required',
        );
      }
      final event = await buildSignedEvent.execute(
        parentFingerprint: parentFingerprint,
        xprvBase58: xprvBase58,
        now: now,
      );
      final acceptedByAnyRelay = await relayRepository.publish(
        event: event,
        relayUrls: normalizedRelayUrls,
      );
      if (!acceptedByAnyRelay) {
        throw KeychainManifestNostrPublishException(
          'failed to publish keychain manifest Nostr event',
        );
      }
    } on KeychainManifestException {
      rethrow;
    } catch (e) {
      throw KeychainManifestNostrPublishException(
        'failed to publish keychain manifest Nostr event',
        cause: e,
      );
    }
  }
}
