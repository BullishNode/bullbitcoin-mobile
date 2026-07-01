export 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_policy.dart'
    show NostrRelayPolicy;
export 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_url.dart'
    show NostrRelayUrl;

import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_policy.dart';
import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_url.dart';

class NostrRelayPolicyFacade {
  static const _defaultRelayValues = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
    'wss://relay.snort.social',
    'wss://no.str.cr',
    'wss://relay.primal.net',
    'wss://nostr.wine',
  ];

  const NostrRelayPolicyFacade();

  NostrRelayPolicy getPolicy() {
    return NostrRelayPolicy(
      defaultRelays: _defaultRelayValues
          .map(NostrRelayUrl.new)
          .toSet()
          .toList(growable: false),
      usesThirdPartyPublicRelays: true,
    );
  }
}
