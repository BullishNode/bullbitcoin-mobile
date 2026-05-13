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
/// failed. Feature adapters translate this to feature-level exceptions so the
/// UI can prompt a manual retry.
class NostrPublishFailedException implements Exception {
  final String message;
  NostrPublishFailedException(this.message);
  @override
  String toString() => 'NostrPublishFailedException: $message';
}

class NostrRelayClient {
  const NostrRelayClient();

  /// Publish an already-built Nostr event to the default relays.
  Future<void> publish(Event event) => _broadcast(event);

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
