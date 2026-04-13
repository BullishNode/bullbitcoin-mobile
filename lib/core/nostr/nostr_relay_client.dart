import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nostr/nostr.dart';

// TODO: move relay list to app config so it can be updated without a release
const _defaultRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.nostr.band',
  'wss://no.str.cr',
  'wss://relay.primal.net',
  'wss://relay.nostr.bg',
  'wss://nostr.wine',
];

class NostrRelayClient {
  /// Publish a NIP-05 profile (kind 0 metadata) to default relays.
  /// Best-effort: individual relay failures are logged, not thrown.
  static Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  }) async {
    final keychain = Keychain(privateKeyHex);

    final content = jsonEncode({
      if (name.isNotEmpty) 'name': name,
      if (nip05.isNotEmpty) 'nip05': nip05,
      if (lud16.isNotEmpty) 'lud16': lud16,
    });

    final event = Event.from(
      kind: 0,
      tags: [],
      content: content,
      privkey: keychain.private,
    );

    final message = event.serialize();

    for (final relay in _defaultRelays) {
      try {
        final ws = await WebSocket.connect(relay).timeout(
          const Duration(seconds: 5),
        );
        ws.add(message);
        // Give the relay a moment to process before closing
        await Future.delayed(const Duration(milliseconds: 500));
        await ws.close();
      } catch (e) {
        debugPrint('Failed to publish to $relay: $e');
      }
    }
  }

  /// Clear the NIP-05 profile by publishing an empty kind 0 event.
  static Future<void> clearProfile({
    required String privateKeyHex,
  }) async {
    await publishProfile(
      privateKeyHex: privateKeyHex,
      name: '',
      nip05: '',
      lud16: '',
    );
  }
}
