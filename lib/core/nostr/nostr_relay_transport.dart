import 'dart:async';
import 'dart:convert';

import 'package:nostr/nostr.dart' as nostr;
import 'package:web_socket_channel/web_socket_channel.dart';

typedef NostrRelayConnector = WebSocketChannel Function(Uri uri);

enum NostrRelayPublishStatus { accepted, rejected, timedOut, unavailable }

final class NostrRelayPublishOutcome {
  final Uri relayUri;
  final NostrRelayPublishStatus status;
  final bool contactedRelay;

  const NostrRelayPublishOutcome({
    required this.relayUri,
    required this.status,
    required this.contactedRelay,
  });

  bool get accepted => status == NostrRelayPublishStatus.accepted;
}

enum NostrRelayFetchStatus { completed, timedOut, unavailable }

final class NostrRelayFetchOutcome {
  final Uri relayUri;
  final NostrRelayFetchStatus status;
  final bool contactedRelay;
  final bool completedByEose;
  final List<nostr.Event> events;

  NostrRelayFetchOutcome({
    required this.relayUri,
    required this.status,
    required this.contactedRelay,
    required this.completedByEose,
    required List<nostr.Event> events,
  }) : events = List.unmodifiable(events);

  bool get hasUsableResponse =>
      contactedRelay && status != NostrRelayFetchStatus.unavailable;
}

class NostrRelayTransport {
  final NostrRelayConnector connect;

  const NostrRelayTransport({this.connect = WebSocketChannel.connect});

  Future<NostrRelayPublishOutcome> publish({
    required Uri relayUri,
    required String eventMessage,
    required String eventId,
    required Duration timeout,
  }) async {
    WebSocketChannel? channel;
    var contactedRelay = false;
    try {
      channel = connect(relayUri);
      await channel.ready.timeout(timeout);
      contactedRelay = true;
      channel.sink.add(eventMessage);
      final response = await channel.stream
          .firstWhere((message) => _isOkForEvent(message, eventId))
          .timeout(timeout);
      return NostrRelayPublishOutcome(
        relayUri: relayUri,
        status: _isAcceptedOk(response)
            ? NostrRelayPublishStatus.accepted
            : NostrRelayPublishStatus.rejected,
        contactedRelay: contactedRelay,
      );
    } on TimeoutException {
      return NostrRelayPublishOutcome(
        relayUri: relayUri,
        status: NostrRelayPublishStatus.timedOut,
        contactedRelay: contactedRelay,
      );
    } catch (_) {
      return NostrRelayPublishOutcome(
        relayUri: relayUri,
        status: NostrRelayPublishStatus.unavailable,
        contactedRelay: contactedRelay,
      );
    } finally {
      await _close(channel, timeout: timeout);
    }
  }

  Future<NostrRelayFetchOutcome> fetch({
    required Uri relayUri,
    required String requestMessage,
    required String subscriptionId,
    required int limit,
    required int maxFrameBytes,
    required Duration timeout,
  }) async {
    if (limit <= 0) throw ArgumentError.value(limit, 'limit');
    if (maxFrameBytes <= 0) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes');
    }

    WebSocketChannel? channel;
    StreamIterator<Object?>? iterator;
    var contactedRelay = false;
    try {
      channel = connect(relayUri);
      await channel.ready.timeout(timeout);
      contactedRelay = true;
      channel.sink.add(requestMessage);
      final events = <nostr.Event>[];
      final deadline = DateTime.now().add(timeout);
      var shouldStop = false;
      var completedByEose = false;
      var timedOut = false;
      iterator = StreamIterator<Object?>(channel.stream);
      while (!shouldStop) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          timedOut = true;
          break;
        }
        var moveTimedOut = false;
        final hasMessage = await iterator.moveNext().timeout(
          remaining,
          onTimeout: () {
            moveTimedOut = true;
            return false;
          },
        );
        if (moveTimedOut) {
          timedOut = true;
          break;
        }
        if (!hasMessage) break;
        final message = iterator.current;
        if (message is String && utf8.encode(message).length > maxFrameBytes) {
          continue;
        }
        final parsed = _message(message);
        if (parsed == null) continue;
        switch (parsed.messageType) {
          case nostr.MessageType.event:
            final event = parsed.message;
            if (event is nostr.Event &&
                event.subscriptionId == subscriptionId) {
              events.add(event);
              if (events.length >= limit) shouldStop = true;
            }
          case nostr.MessageType.eose:
            final eose = parsed.message;
            if (eose is nostr.Eose && eose.subscriptionId == subscriptionId) {
              completedByEose = true;
              shouldStop = true;
            }
          case nostr.MessageType.closed:
            final closed = parsed.message;
            if (closed is Map && closed['subscriptionId'] == subscriptionId) {
              shouldStop = true;
            }
          case nostr.MessageType.req:
          case nostr.MessageType.close:
          case nostr.MessageType.notice:
          case nostr.MessageType.ok:
          case nostr.MessageType.auth:
            break;
        }
      }
      return NostrRelayFetchOutcome(
        relayUri: relayUri,
        status: timedOut
            ? NostrRelayFetchStatus.timedOut
            : NostrRelayFetchStatus.completed,
        contactedRelay: contactedRelay,
        completedByEose: completedByEose,
        events: events,
      );
    } on TimeoutException {
      return NostrRelayFetchOutcome(
        relayUri: relayUri,
        status: NostrRelayFetchStatus.timedOut,
        contactedRelay: contactedRelay,
        completedByEose: false,
        events: const [],
      );
    } catch (_) {
      return NostrRelayFetchOutcome(
        relayUri: relayUri,
        status: NostrRelayFetchStatus.unavailable,
        contactedRelay: contactedRelay,
        completedByEose: false,
        events: const [],
      );
    } finally {
      await iterator?.cancel().catchError((_) {});
      await _close(channel, timeout: timeout, subscriptionId: subscriptionId);
    }
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

  Future<void> _close(
    WebSocketChannel? channel, {
    required Duration timeout,
    String? subscriptionId,
  }) async {
    if (channel == null) return;
    if (subscriptionId != null) {
      try {
        channel.sink.add(nostr.Close(subscriptionId).serialize());
      } catch (_) {}
    }
    await channel.sink.close().timeout(timeout).catchError((_) {});
  }
}
