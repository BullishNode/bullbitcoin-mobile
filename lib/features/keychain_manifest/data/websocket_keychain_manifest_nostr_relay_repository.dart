import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';

class WebSocketKeychainManifestNostrRelayRepository
    implements KeychainManifestNostrRelayRepository {
  static const _fetchLimit = 20;

  final KeychainManifestNostrRelayDatasource _datasource;
  final KeychainManifestNostrSignedEventCodec _eventCodec;
  final Duration _timeout;

  const WebSocketKeychainManifestNostrRelayRepository({
    KeychainManifestNostrRelayDatasource datasource =
        const KeychainManifestNostrRelayDatasource(),
    KeychainManifestNostrSignedEventCodec eventCodec =
        const KeychainManifestNostrSignedEventCodec(),
    Duration timeout = const Duration(seconds: 10),
  }) : this._(datasource, eventCodec, timeout);

  const WebSocketKeychainManifestNostrRelayRepository._(
    this._datasource,
    this._eventCodec,
    this._timeout,
  );

  @override
  Future<bool> publish({
    required KeychainManifestNostrSignedEvent event,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    final uniqueRelayUrls = relayUrls.toSet().toList(growable: false);
    final eventMessage = _eventCodec.serialize(event);
    final outcomes = await Future.wait(
      uniqueRelayUrls.map((relayUrl) async {
        try {
          return await _datasource.publish(
            relayUri: relayUrl.uri,
            eventMessage: eventMessage,
            eventId: event.id,
            timeout: _timeout,
          );
        } catch (_) {
          return false;
        }
      }),
    );
    return outcomes.any((accepted) => accepted);
  }

  @override
  Future<KeychainManifestNostrFetchResult> fetchManifestEvents({
    required String authorPublicKeyHex,
    required List<KeychainManifestNostrRelayUrl> relayUrls,
  }) async {
    final uniqueRelayUrls = relayUrls.toSet().toList(growable: false);
    final normalizedAuthor = authorPublicKeyHex.trim().toLowerCase();
    final eventsById = <String, KeychainManifestNostrSignedEvent>{};
    var contactedAnyRelay = false;
    await Future.wait(
      uniqueRelayUrls.map((relayUrl) async {
        try {
          final events = await _datasource.fetchManifestEvents(
            relayUri: relayUrl.uri,
            subscriptionId: 'keychain-manifest-${normalizedAuthor.hashCode}',
            authorPublicKeyHex: normalizedAuthor,
            limit: _fetchLimit,
            timeout: _timeout,
          );
          contactedAnyRelay = true;
          for (final event in events) {
            try {
              final manifestEvent = _eventCodec.fromNostrEvent(event);
              if (manifestEvent.authorPublicKeyHex == normalizedAuthor) {
                eventsById[manifestEvent.id] = manifestEvent;
              }
            } catch (_) {
              continue;
            }
          }
        } catch (_) {
          return;
        }
      }),
    );
    final events = eventsById.values.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return KeychainManifestNostrFetchResult(
      contactedAnyRelay: contactedAnyRelay,
      events: events,
    );
  }
}
