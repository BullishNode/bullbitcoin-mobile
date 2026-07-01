import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_url.dart';

final class NostrRelayPolicy {
  final List<NostrRelayUrl> defaultRelays;
  final bool usesThirdPartyPublicRelays;

  NostrRelayPolicy({
    required Iterable<NostrRelayUrl> defaultRelays,
    required this.usesThirdPartyPublicRelays,
  }) : defaultRelays = List.unmodifiable(defaultRelays);
}
