import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/models/keychain_manifest_nostr_event_model.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/repositories/keychain_manifest_nostr_relay_repository.dart';

class WebSocketKeychainManifestNostrRelayRepository
    implements KeychainManifestNostrRelayRepository {
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
}
