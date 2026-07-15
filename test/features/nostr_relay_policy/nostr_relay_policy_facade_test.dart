import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns approved default app Nostr relay policy', () {
    final policy = const NostrRelayPolicyFacade().getPolicy();

    expect(policy.defaultRelays.map((relay) => relay.url), [
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.nostr.band',
      'wss://relay.snort.social',
      'wss://no.str.cr',
      'wss://relay.primal.net',
      'wss://nostr.wine',
    ]);
    expect(
      policy.defaultRelays.every((relay) => relay.uri.scheme == 'wss'),
      isTrue,
    );
    expect(policy.usesThirdPartyPublicRelays, isTrue);
    expect(
      () => policy.defaultRelays.add(NostrRelayUrl('wss://relay.example')),
      throwsUnsupportedError,
    );
  });

  test('canonicalizes relay URLs before equality and deduplication', () {
    expect(
      NostrRelayUrl('WSS://Relay.Example:443/'),
      NostrRelayUrl('wss://relay.example'),
    );
    expect(
      NostrRelayUrl('wss://relay.example:444'),
      isNot(NostrRelayUrl('wss://relay.example')),
    );
  });

  test('uses comma-separated relay override when provided', () {
    final policy = const NostrRelayPolicyFacade(
      relayUrlsOverride: ' wss://relay.example , wss://relay2.example/ ',
    ).getPolicy();

    expect(policy.defaultRelays.map((relay) => relay.url), [
      'wss://relay.example',
      'wss://relay2.example',
    ]);
    expect(policy.usesThirdPartyPublicRelays, isTrue);
  });

  test('deduplicates configured relay overrides after canonicalization', () {
    final policy = const NostrRelayPolicyFacade(
      relayUrlsOverride: 'wss://relay.example,wss://relay.example:443/',
    ).getPolicy();

    expect(policy.defaultRelays.map((relay) => relay.url), [
      'wss://relay.example',
    ]);
  });

  test('rejects unsupported relay URL forms', () {
    expect(
      () => NostrRelayUrl('ws://relay.example'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => NostrRelayUrl('https://relay.example'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => NostrRelayUrl('wss://relay.example?token=secret'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => NostrRelayUrl('wss://relay.example#keychain'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => NostrRelayUrl('wss://user:pass@relay.example'),
      throwsA(isA<Exception>()),
    );
  });
}
