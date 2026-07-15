import 'dart:async';
import 'dart:convert';

import 'package:bb_mobile/features/keychain_manifest/domain/entities/keychain_manifest_nostr_event.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:web_socket_channel/web_socket_channel.dart';

typedef KeychainManifestNostrRelayConnector =
    WebSocketChannel Function(Uri uri);

class KeychainManifestNostrRelayDatasource {
  /// Reject any relay frame larger than this before deserializing or
  /// decrypting it (P21b). Comfortably above any real manifest event, but
  /// bounded so a hostile relay cannot stream oversize payloads to exhaust
  /// memory/CPU (sha256 + bip340 per event) during recovery.
  static const int maxEventFrameBytes = 256 * 1024;

  final KeychainManifestNostrRelayConnector connect;

  const KeychainManifestNostrRelayDatasource({
    this.connect = WebSocketChannel.connect,
  });

  Future<bool> publish({
    required Uri relayUri,
    required String eventMessage,
    required String eventId,
    required Duration timeout,
  }) async {
    final channel = connect(relayUri);
    try {
      await channel.ready.timeout(timeout);
      channel.sink.add(eventMessage);
      final response = await channel.stream
          .firstWhere((message) => _isOkForEvent(message, eventId))
          .timeout(timeout);
      return _isAcceptedOk(response);
    } finally {
      await channel.sink.close().timeout(timeout).catchError((_) {});
    }
  }

  Future<List<nostr.Event>> fetchManifestEvents({
    required Uri relayUri,
    required String subscriptionId,
    required String authorPublicKeyHex,
    required int limit,
    required Duration timeout,
  }) async {
    final channel = connect(relayUri);
    StreamIterator<Object?>? iterator;
    try {
      await channel.ready.timeout(timeout);
      channel.sink.add(
        _manifestRequest(
          subscriptionId: subscriptionId,
          authorPublicKeyHex: authorPublicKeyHex,
          limit: limit,
        ),
      );
      final events = <nostr.Event>[];
      final deadline = DateTime.now().add(timeout);
      var reachedEndOfStoredEvents = false;
      iterator = StreamIterator<Object?>(channel.stream);
      while (!reachedEndOfStoredEvents) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final hasMessage = await iterator.moveNext().timeout(
          remaining,
          onTimeout: () => false,
        );
        if (!hasMessage) break;
        final message = iterator.current;
        // P21b: reject oversize frames before deserialize/verify/decrypt work.
        if (message is String && message.length > maxEventFrameBytes) continue;
        final parsed = _message(message);
        if (parsed == null) continue;
        switch (parsed.messageType) {
          case nostr.MessageType.event:
            final event = parsed.message;
            if (event is nostr.Event &&
                event.subscriptionId == subscriptionId) {
              events.add(event);
              // P21b: `limit` is only a REQ hint; enforce the ceiling
              // client-side so a relay cannot stream past it to timeout.
              if (events.length >= limit) reachedEndOfStoredEvents = true;
            }
          case nostr.MessageType.eose:
            final eose = parsed.message;
            if (eose is nostr.Eose && eose.subscriptionId == subscriptionId) {
              reachedEndOfStoredEvents = true;
            }
          case nostr.MessageType.closed:
            final closed = parsed.message;
            if (closed is Map && closed['subscriptionId'] == subscriptionId) {
              reachedEndOfStoredEvents = true;
            }
          case nostr.MessageType.req:
          case nostr.MessageType.close:
          case nostr.MessageType.notice:
          case nostr.MessageType.ok:
          case nostr.MessageType.auth:
            break;
        }
      }
      return events;
    } finally {
      await iterator?.cancel().catchError((_) {});
      channel.sink.add(nostr.Close(subscriptionId).serialize());
      await channel.sink.close().timeout(timeout).catchError((_) {});
    }
  }

  String _manifestRequest({
    required String subscriptionId,
    required String authorPublicKeyHex,
    required int limit,
  }) {
    return jsonEncode([
      'REQ',
      subscriptionId,
      {
        'authors': [authorPublicKeyHex],
        'kinds': [keychainManifestNostrEventKind],
        '#d': [keychainManifestNostrDTag],
        'limit': limit,
      },
    ]);
  }

  bool _isOkForEvent(Object? message, String eventId) {
    final result = _commandResult(message);
    return result != null && result.eventId == eventId;
  }

  bool _isAcceptedOk(Object? message) {
    return _commandResult(message)?.status == true;
  }

  nostr.Nip20? _commandResult(Object? message) {
    final decoded = _message(message);
    if (decoded == null || decoded.messageType != nostr.MessageType.ok) {
      return null;
    }
    final result = decoded.message;
    if (result is nostr.Nip20) return result;
    return null;
  }

  nostr.Message? _message(Object? message) {
    if (message is! String) return null;
    try {
      return nostr.Message.deserialize(message);
    } catch (_) {
      return null;
    }
  }
}
