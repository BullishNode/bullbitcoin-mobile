import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:bb_mobile/features/keychain_manifest/data/websocket_keychain_manifest_nostr_relay_repository.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_ciphertext.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_relay.dart';
import 'package:flutter_test/flutter_test.dart';

final _wellShapedCiphertext = base64.encode(
  Uint8List(KeychainManifestNostrCiphertext.minimumByteLength),
);

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

  test('publish frame carries only clean public metadata', () async {
    // P18a: the last boundary before the wire. The serialized ['EVENT', ...]
    // frame must expose only public Nostr metadata - kind 30078, the d-tag
    // 'manifest', author pubkey and createdAt - with the content field a bare
    // base64 ciphertext and no bullbitcoin/recoverbull marker anywhere.
    final datasource = _FakeKeychainManifestNostrRelayDatasource({
      'wss://accepted.example': true,
    });
    final repository = WebSocketKeychainManifestNostrRelayRepository(
      datasource: datasource,
    );

    await repository.publish(
      event: _signedEvent(),
      relayUrls: [KeychainManifestNostrRelayUrl('wss://accepted.example')],
    );

    final frame = datasource.eventMessages.single;
    expect(frame, isNot(contains('bullbitcoin')));
    expect(frame, isNot(contains('recoverbull')));

    final decoded = jsonDecode(frame) as List<Object?>;
    expect(decoded.first, 'EVENT');
    final event = decoded[1]! as Map<String, Object?>;
    expect(event.keys.toSet(), {
      'id',
      'pubkey',
      'created_at',
      'kind',
      'tags',
      'content',
      'sig',
    });
    expect(event['kind'], keychainManifestNostrEventKind);
    expect(event['tags'], [
      ['d', keychainManifestNostrDTag],
    ]);
    expect(event['content'], _wellShapedCiphertext);
    expect(() => base64.decode(event['content']! as String), returnsNormally);
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
    encryptedContent: KeychainManifestNostrCiphertext(_wellShapedCiphertext),
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
