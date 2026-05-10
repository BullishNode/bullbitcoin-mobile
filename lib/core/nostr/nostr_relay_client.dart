import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nostr/nostr.dart';

// TODO: move relay list to app config so it can be updated without a release
const _defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
  'wss://relay.snort.social',
  'wss://no.str.cr',
  'wss://relay.primal.net',
  'wss://nostr.wine',
];

/// Thrown when a publish attempt reached zero relays — every connect or send
/// failed. Callers (see `RegisterLightningAddressUsecase` /
/// `DeleteLightningAddressUsecase`) translate this to a feature-level
/// exception so the UI can prompt a manual retry.
class NostrPublishFailedException implements Exception {
  final String message;
  NostrPublishFailedException(this.message);
  @override
  String toString() => 'NostrPublishFailedException: $message';
}

class NostrRelayClient {
  const NostrRelayClient();

  /// Publish a NIP-05 profile (kind 0 metadata) to default relays.
  ///
  /// Empty fields are written as explicit empty strings (`""`) — not omitted
  /// — so clients that merge kind 0 fields (rather than replacing) drop any
  /// stale `nip05` / `lud16` claims. Throws [NostrPublishFailedException]
  /// when the event could not be sent to any relay.
  Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  }) async {
    final keys = Keys(privateKeyHex);

    final content = jsonEncode({'name': name, 'nip05': nip05, 'lud16': lud16});

    final event = Event.from(
      kind: 0,
      tags: [],
      content: content,
      secretKey: keys.secret,
    );

    await _broadcast(event);
  }

  /// Clear the NIP-05 profile by publishing a kind 0 event with explicit
  /// empty `name`, `nip05`, `lud16` fields. The empty strings (rather than
  /// field omission) defeat clients that merge kind 0 contents instead of
  /// replacing them.
  Future<void> clearProfile({required String privateKeyHex}) async {
    await publishProfile(
      privateKeyHex: privateKeyHex,
      name: '',
      nip05: '',
      lud16: '',
    );
  }

  Future<void> _broadcast(Event event) async {
    final message = event.serialize();
    var acked = 0;
    for (final relay in _defaultRelays) {
      try {
        final ws = await WebSocket.connect(
          relay,
        ).timeout(const Duration(seconds: 5));
        ws.add(message);
        // Give the relay a moment to process before closing
        await Future.delayed(const Duration(milliseconds: 500));
        await ws.close();
        acked++;
      } catch (e) {
        debugPrint('Failed to publish to $relay: $e');
      }
    }
    if (acked == 0) {
      throw NostrPublishFailedException(
        'no relay accepted the broadcast '
        '(attempted ${_defaultRelays.length})',
      );
    }
  }
}
