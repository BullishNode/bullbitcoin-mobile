import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes signed events and succeeds when any relay accepts', () async {
    final datasource = _FakeKeychainManifestNostrRelayDatasource({
      'wss://accepted.example': true,
      'wss://failed.example': false,
    });
    final repository = WebSocketKeychainManifestNostrRelayRepository(
      datasource: datasource,
    );

    final result = await repository.publish(
      event: _signedEvent(),
      relayUrls: [
        KeychainManifestNostrRelayUrl('wss://accepted.example'),
        KeychainManifestNostrRelayUrl('wss://failed.example'),
        KeychainManifestNostrRelayUrl('wss://accepted.example'),
      ],
    );

    expect(result, isTrue);
    expect(datasource.eventMessages, hasLength(2));
    expect(datasource.eventMessages, everyElement(contains('"EVENT"')));
  });

  test('treats relay exceptions as failed relay attempts', () async {
    final datasource = _FakeKeychainManifestNostrRelayDatasource({
      'wss://accepted.example': true,
    })..errorRelays.add('wss://error.example');
    final repository = WebSocketKeychainManifestNostrRelayRepository(
      datasource: datasource,
    );

    final result = await repository.publish(
      event: _signedEvent(),
      relayUrls: [
        KeychainManifestNostrRelayUrl('wss://accepted.example'),
        KeychainManifestNostrRelayUrl('wss://error.example'),
      ],
    );

    expect(result, isTrue);
  });

  test('fails when no relay accepts', () async {
    final datasource = _FakeKeychainManifestNostrRelayDatasource({
      'wss://failed.example': false,
    });
    final repository = WebSocketKeychainManifestNostrRelayRepository(
      datasource: datasource,
    );

    final result = await repository.publish(
      event: _signedEvent(),
      relayUrls: [KeychainManifestNostrRelayUrl('wss://failed.example')],
    );

    expect(result, isFalse);
  });
}

KeychainManifestNostrSignedEvent _signedEvent() {
  final draft = KeychainManifestNostrEventDraft(
    authorPublicKeyHex:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    encryptedContent: 'encrypted-payload',
    createdAt: 123,
  );
  return KeychainManifestNostrSignedEvent.fromDraft(
    draft: draft,
    signatureHex:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  );
}

class _FakeKeychainManifestNostrRelayDatasource
    extends KeychainManifestNostrRelayDatasource {
  final Map<String, bool> relayResults;
  final errorRelays = <String>{};
  final eventMessages = <String>[];

  _FakeKeychainManifestNostrRelayDatasource(this.relayResults);

  @override
  Future<bool> publish({
    required Uri relayUri,
    required String eventMessage,
    required String eventId,
    required Duration timeout,
  }) async {
    eventMessages.add(eventMessage);
    if (errorRelays.contains(relayUri.toString())) {
      throw StateError('relay-secret-leak');
    }
    return relayResults[relayUri.toString()] ?? false;
  }
}
