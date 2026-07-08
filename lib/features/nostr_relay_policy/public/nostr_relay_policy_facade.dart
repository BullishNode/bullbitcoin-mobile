export 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_policy.dart'
    show NostrRelayPolicy;
export 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_url.dart'
    show NostrRelayUrl;

import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_policy.dart';
import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_url.dart';

const nostrRelayUrlsEnvironmentKey = 'NOSTR_RELAY_URLS';

class NostrRelayPolicyFacade {
  static const _relayUrlsOverride = String.fromEnvironment(
    nostrRelayUrlsEnvironmentKey,
  );
  static const _defaultRelayValues = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
    'wss://relay.snort.social',
    'wss://no.str.cr',
    'wss://relay.primal.net',
    'wss://nostr.wine',
  ];

  final String _relayUrlsOverrideValue;

  const NostrRelayPolicyFacade({String relayUrlsOverride = _relayUrlsOverride})
    : _relayUrlsOverrideValue = relayUrlsOverride;

  NostrRelayPolicy getPolicy() {
    final relayValues = _configuredRelayValues();
    return NostrRelayPolicy(
      defaultRelays: relayValues
          .map(NostrRelayUrl.new)
          .toSet()
          .toList(growable: false),
      usesThirdPartyPublicRelays: true,
    );
  }

  Iterable<String> _configuredRelayValues() {
    final configured = _relayUrlsOverrideValue.trim();
    if (configured.isEmpty) return _defaultRelayValues;
    return configured
        .split(',')
        .map((relay) => relay.trim())
        .where((relay) => relay.isNotEmpty);
  }
}
