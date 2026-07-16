import 'dart:async';
import 'dart:convert';

import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('drops EVENT frames whose signature does not verify', () async {
    final valid = _signedEventFrame(content: 'genuine', createdAt: 20);
    final tampered = _signedEventFrame(
      content: 'genuine',
      createdAt: 30,
    ).replaceFirst('"content":"genuine"', '"content":"tampered"');
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      channel.addIncoming(valid);
      channel.addIncoming(tampered);
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await _fetch(transport);

    expect(outcome.status, NostrRelayFetchStatus.completed);
    expect(outcome.completedByEose, isTrue);
    expect(outcome.events, hasLength(1));
    expect(outcome.events.single.content, 'genuine');
  });

  test('stops collecting at the caller event limit', () async {
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      for (var i = 0; i < 5; i++) {
        channel.addIncoming(
          _signedEventFrame(content: 'e$i', createdAt: 20 + i),
        );
      }
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await _fetch(transport, limit: 2);

    expect(outcome.status, NostrRelayFetchStatus.completed);
    expect(outcome.completedByEose, isFalse);
    expect(outcome.events, hasLength(2));
  });

  test('rejects an oversize frame before deserializing it', () async {
    final oversize =
        '["EVENT","$_subId",{"content":"'
        '${'A' * (_maxFrameBytes + 1)}'
        '"}]';
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      channel.addIncoming(oversize);
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await _fetch(transport);

    expect(outcome.events, isEmpty);
  });

  test('measures the frame bound in UTF-8 bytes', () async {
    final frame = _signedEventFrame(content: 'é' * 600, createdAt: 20);
    expect(utf8.encode(frame).length, greaterThan(frame.length));
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      channel.addIncoming(frame);
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await _fetch(transport, maxFrameBytes: frame.length);

    expect(outcome.events, isEmpty);
  });

  test('reports an overall OK wait timeout without throwing', () async {
    final channel = _FakeWebSocketChannel();
    Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (timer.tick >= 20 || channel.isClosed) {
        timer.cancel();
        return;
      }
      channel.addIncoming('["NOTICE","still not an OK"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await transport.publish(
      relayUri: _relayUri,
      eventMessage: '["EVENT",{}]',
      eventId: _eventId,
      timeout: const Duration(milliseconds: 10),
    );

    expect(outcome.status, NostrRelayPublishStatus.timedOut);
    expect(outcome.contactedRelay, isTrue);
  });

  test('does not let close failure mask an accepted relay OK', () async {
    final channel = _FakeWebSocketChannel(closeError: StateError('close leak'));
    final transport = NostrRelayTransport(connect: (_) => channel);
    Future<void>.microtask(
      () => channel.addIncoming('["OK","$_eventId",true,""]'),
    );

    final outcome = await transport.publish(
      relayUri: _relayUri,
      eventMessage: '["EVENT",{}]',
      eventId: _eventId,
      timeout: const Duration(milliseconds: 50),
    );

    expect(outcome.status, NostrRelayPublishStatus.accepted);
  });

  test('distinguishes relay rejection from unavailability', () async {
    final rejectedChannel = _FakeWebSocketChannel();
    final rejectedTransport = NostrRelayTransport(
      connect: (_) => rejectedChannel,
    );
    Future<void>.microtask(
      () => rejectedChannel.addIncoming('["OK","$_eventId",false,"blocked"]'),
    );

    final rejected = await rejectedTransport.publish(
      relayUri: _relayUri,
      eventMessage: '["EVENT",{}]',
      eventId: _eventId,
      timeout: const Duration(milliseconds: 50),
    );
    final unavailable =
        await NostrRelayTransport(
          connect: (_) => throw StateError('offline'),
        ).publish(
          relayUri: _relayUri,
          eventMessage: '["EVENT",{}]',
          eventId: _eventId,
          timeout: const Duration(milliseconds: 50),
        );

    expect(rejected.status, NostrRelayPublishStatus.rejected);
    expect(unavailable.status, NostrRelayPublishStatus.unavailable);
    expect(unavailable.contactedRelay, isFalse);
  });

  test('returns partial fetch state at the overall deadline', () async {
    final channel = _FakeWebSocketChannel();
    Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (timer.tick >= 20 || channel.isClosed) {
        timer.cancel();
        return;
      }
      channel.addIncoming('["NOTICE","still not an EOSE"]');
    });
    final transport = NostrRelayTransport(connect: (_) => channel);

    final outcome = await _fetch(
      transport,
      timeout: const Duration(milliseconds: 10),
    );

    expect(outcome.status, NostrRelayFetchStatus.timedOut);
    expect(outcome.completedByEose, isFalse);
    expect(outcome.hasUsableResponse, isTrue);
    expect(outcome.events, isEmpty);
    expect(channel.isClosed, isTrue);
  });
}

Future<NostrRelayFetchOutcome> _fetch(
  NostrRelayTransport transport, {
  int limit = 20,
  int maxFrameBytes = _maxFrameBytes,
  Duration timeout = const Duration(milliseconds: 200),
}) {
  return transport.fetch(
    relayUri: _relayUri,
    requestMessage: '["REQ","$_subId",{}]',
    subscriptionId: _subId,
    limit: limit,
    maxFrameBytes: maxFrameBytes,
    timeout: timeout,
  );
}

const _maxFrameBytes = 256 * 1024;
const _eventId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _subId = 'manifest-sub';
const _secretKey =
    '0000000000000000000000000000000000000000000000000000000000000001';
final _relayUri = Uri.parse('wss://relay.example');

String _signedEventFrame({required String content, required int createdAt}) {
  final event = nostr.Event.from(
    kind: 30078,
    content: content,
    secretKey: _secretKey,
    createdAt: createdAt,
    tags: const [
      ['d', 'manifest'],
    ],
    subscriptionId: _subId,
  );
  return event.serialize();
}

class _FakeWebSocketChannel
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  final _incoming = StreamController<Object?>();
  final _sink = _FakeWebSocketSink();
  final Object? closeError;

  _FakeWebSocketChannel({this.closeError}) {
    _sink.closeError = closeError;
  }

  bool get isClosed => _sink.closed;

  void addIncoming(Object? message) {
    if (!_incoming.isClosed) _incoming.add(message);
  }

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<Object?> get stream => _incoming.stream;
}

class _FakeWebSocketSink implements WebSocketSink {
  final sent = <Object?>[];
  final _done = Completer<void>();
  Object? closeError;
  bool closed = false;

  @override
  Future<void> get done => _done.future;

  @override
  void add(Object? event) {
    sent.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    closed = true;
    final error = closeError;
    if (error != null) throw error;
    if (!_done.isCompleted) _done.complete();
  }
}
