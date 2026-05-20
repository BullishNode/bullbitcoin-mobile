import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart';

void main() {
  test('rejects empty fetch filters', () async {
    const client = NostrRelayClient();

    await expectLater(
      client.fetch(filter: Filter()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('serializes tag filters into the Nostr request filter', () {
    final request = serializeNostrRelayRequest(
      subscriptionId: 'sub',
      filter: Filter(
        authors: const ['author'],
        kinds: const [30078],
        limit: 10,
      ),
      tagFilters: const {
        'd': ['manifest'],
      },
    );

    expect(
      request,
      '["REQ","sub",{"authors":["author"],"kinds":[30078],'
      '"limit":10,"#d":["manifest"]}]',
    );
  });
}
