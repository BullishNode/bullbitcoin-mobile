import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_errors.dart';
import 'package:bb_mobile/features/lightning_address/interface_adapters/relay_nostr_publish_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';

class _FakeRelayClient extends NostrRelayClient {
  _FakeRelayClient({this.error});

  final NostrPublishFailedException? error;
  Event? published;

  @override
  Future<void> publish(Event event) async {
    final error = this.error;
    if (error != null) throw error;
    published = event;
  }
}

void main() {
  const secretKeyHex =
      '0000000000000000000000000000000000000000000000000000000000000001';

  late NostrKeychainHandle handle;

  setUp(() {
    handle = NostrKeychainHandle.fromSecretKeyHex(secretKeyHex);
  });

  test('publishes LA NIP-05 profile metadata as a kind 0 event', () async {
    final relayClient = _FakeRelayClient();
    final adapter = RelayNostrPublishAdapter(relayClient: relayClient);

    await adapter.publishProfile(
      handle: handle,
      name: 'alice',
      nip05: 'alice@bullpay.ca',
      lud16: 'alice@bullpay.ca',
    );

    final event = relayClient.published;
    expect(event, isNotNull);
    expect(event!.kind, 0);
    expect(event.tags, isEmpty);
    expect(event.pubkey, handle.publicKeyHex);
    expect(jsonDecode(event.content), {
      'name': 'alice',
      'nip05': 'alice@bullpay.ca',
      'lud16': 'alice@bullpay.ca',
    });
  });

  test('clears profile metadata with explicit empty strings', () async {
    final relayClient = _FakeRelayClient();
    final adapter = RelayNostrPublishAdapter(relayClient: relayClient);

    await adapter.clearProfile(handle: handle);

    final event = relayClient.published;
    expect(event, isNotNull);
    expect(event!.kind, 0);
    expect(jsonDecode(event.content), {'name': '', 'nip05': '', 'lud16': ''});
  });

  test('maps relay publish failures to LA domain failures', () async {
    final adapter = RelayNostrPublishAdapter(
      relayClient: _FakeRelayClient(
        error: NostrPublishFailedException('no relay accepted'),
      ),
    );

    await expectLater(
      adapter.clearProfile(handle: handle),
      throwsA(isA<LightningAddressNostrPublishFailedException>()),
    );
  });
}
