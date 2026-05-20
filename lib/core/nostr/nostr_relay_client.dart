import 'dart:async';
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
/// failed. Feature adapters translate this to feature-level exceptions so the
/// UI can prompt a manual retry.
class NostrPublishFailedException implements Exception {
  final String message;
  NostrPublishFailedException(this.message);
  @override
  String toString() => 'NostrPublishFailedException: $message';
}

class NostrFetchFailedException implements Exception {
  final String message;
  NostrFetchFailedException(this.message);
  @override
  String toString() => 'NostrFetchFailedException: $message';
}

enum NostrPublishConfirmation { sent, accepted }

class NostrRelayClient {
  const NostrRelayClient();

  /// Publish an already-built Nostr event to the default relays.
  Future<void> publish(
    Event event, {
    NostrPublishConfirmation confirmation = NostrPublishConfirmation.sent,
  }) {
    return switch (confirmation) {
      NostrPublishConfirmation.sent => _broadcastSent(event),
      NostrPublishConfirmation.accepted => _broadcastAccepted(event),
    };
  }

  Future<List<Event>> fetch({
    required Filter filter,
    Map<String, List<String>> tagFilters = const {},
  }) async {
    final subscriptionId = 'bb-${DateTime.now().microsecondsSinceEpoch}';
    final request = serializeNostrRelayRequest(
      subscriptionId: subscriptionId,
      filter: filter,
      tagFilters: tagFilters,
    );
    final eventsById = <String, Event>{};
    final results = await Future.wait<List<Event>?>([
      for (final relay in _defaultRelays)
        _fetchFromRelay(relay, request, subscriptionId)
            .then<List<Event>?>((events) {
              return events;
            })
            .catchError((e) {
              debugPrint('Failed to fetch from $relay: $e');
              return null;
            }),
    ]);

    for (final events in results) {
      if (events == null) continue;
      for (final event in events) {
        eventsById[event.id] = event;
      }
    }

    if (results.whereType<List<Event>>().isEmpty) {
      throw NostrFetchFailedException(
        'no relay answered the query (attempted ${_defaultRelays.length})',
      );
    }

    return eventsById.values.toList();
  }

  Future<void> _broadcastSent(Event event) async {
    final message = event.serialize();
    var reached = 0;
    await Future.wait([
      for (final relay in _defaultRelays)
        _sendToRelay(relay, message)
            .then((_) {
              reached++;
            })
            .catchError((e) {
              debugPrint('Failed to publish to $relay: $e');
            }),
    ]);
    if (reached == 0) {
      throw NostrPublishFailedException(
        'no relay accepted the connection '
        '(attempted ${_defaultRelays.length})',
      );
    }
  }

  Future<void> _broadcastAccepted(Event event) async {
    final message = event.serialize();
    final results = await Future.wait([
      for (final relay in _defaultRelays)
        _publishToRelay(relay, message, event.id).catchError((e) {
          debugPrint('Failed to publish to $relay: $e');
          return false;
        }),
    ]);
    final acked = results.where((accepted) => accepted).length;
    if (acked == 0) {
      throw NostrPublishFailedException(
        'no relay accepted the broadcast '
        '(attempted ${_defaultRelays.length})',
      );
    }
  }

  Future<void> _sendToRelay(String relay, String message) async {
    final ws = await WebSocket.connect(
      relay,
    ).timeout(const Duration(seconds: 5));

    try {
      ws.add(message);
      await Future.delayed(const Duration(milliseconds: 500));
    } finally {
      await ws.close();
    }
  }

  Future<bool> _publishToRelay(
    String relay,
    String message,
    String eventId,
  ) async {
    final ws = await WebSocket.connect(
      relay,
    ).timeout(const Duration(seconds: 5));

    try {
      ws.add(message);
      final deadline = Timer(const Duration(seconds: 15), () {
        ws.close();
      });
      try {
        await for (final raw in ws.timeout(const Duration(seconds: 5))) {
          if (raw is! String) continue;
          try {
            final relayMessage = Message.deserialize(raw);
            if (relayMessage.messageType != MessageType.ok) continue;

            final result = relayMessage.message as Nip20;
            if (result.eventId != eventId) continue;
            if (!result.status) {
              debugPrint(
                'Relay $relay rejected event $eventId: ${result.message}',
              );
            }
            return result.status;
          } catch (e) {
            debugPrint(
              'Failed to parse Nostr relay publish ack from $relay: $e',
            );
          }
        }
      } finally {
        deadline.cancel();
      }
    } on TimeoutException {
      return false;
    } finally {
      await ws.close();
    }

    return false;
  }

  Future<List<Event>> _fetchFromRelay(
    String relay,
    String request,
    String subscriptionId,
  ) async {
    final ws = await WebSocket.connect(
      relay,
    ).timeout(const Duration(seconds: 5));
    final events = <Event>[];

    try {
      ws.add(request);
      final deadline = Timer(const Duration(seconds: 15), () {
        ws.close();
      });
      try {
        await for (final raw in ws.timeout(const Duration(seconds: 8))) {
          if (raw is! String) continue;
          try {
            final message = Message.deserialize(raw);
            if (message.messageType == MessageType.event) {
              final event = message.message as Event;
              if (event.subscriptionId == subscriptionId) {
                events.add(event);
              }
            }
            if (message.messageType == MessageType.eose) break;
          } catch (e) {
            debugPrint('Failed to parse Nostr relay message from $relay: $e');
          }
        }
      } on TimeoutException {
        return events;
      } finally {
        deadline.cancel();
      }
      return events;
    } finally {
      await ws.close();
    }
  }
}

@visibleForTesting
String serializeNostrRelayRequest({
  required String subscriptionId,
  required Filter filter,
  required Map<String, List<String>> tagFilters,
}) {
  final json = filter.toJson();
  for (final entry in tagFilters.entries) {
    json['#${entry.key}'] = entry.value;
  }
  if (json.isEmpty) {
    throw ArgumentError.value(
      filter,
      'filter',
      'must contain at least one constraint',
    );
  }

  return jsonEncode(['REQ', subscriptionId, json]);
}
