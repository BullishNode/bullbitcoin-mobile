import 'dart:async';

import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('drops EVENT frames whose signature does not verify (P21a)', () async {
    final valid = _signedEventFrame(content: 'genuine', createdAt: 20);
    // Mutate the content after signing so the frame is authentic-looking but
    // its signature no longer verifies - the recovery authenticity boundary.
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
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    final events = await datasource.fetchManifestEvents(
      relayUri: Uri.parse('wss://relay.example'),
      subscriptionId: _subId,
      authorPublicKeyHex: _authorPubkey,
      limit: 20,
      timeout: const Duration(milliseconds: 200),
    );

    expect(events, hasLength(1));
    expect(events.single.content, 'genuine');
  });

  test('stops collecting at the client-side event limit (P21b)', () async {
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      for (var i = 0; i < 5; i++) {
        channel.addIncoming(
          _signedEventFrame(content: 'e$i', createdAt: 20 + i),
        );
      }
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    final events = await datasource.fetchManifestEvents(
      relayUri: Uri.parse('wss://relay.example'),
      subscriptionId: _subId,
      authorPublicKeyHex: _authorPubkey,
      limit: 2,
      timeout: const Duration(milliseconds: 200),
    );

    expect(events, hasLength(2));
  });

  test('rejects an oversize frame before deserializing it (P21b)', () async {
    final oversize =
        '["EVENT","$_subId",{"content":"'
        '${'A' * (KeychainManifestNostrRelayDatasource.maxEventFrameBytes + 1)}'
        '"}]';
    final channel = _FakeWebSocketChannel();
    Future<void>.microtask(() {
      channel.addIncoming(oversize);
      channel.addIncoming('["EOSE","$_subId"]');
    });
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    final events = await datasource.fetchManifestEvents(
      relayUri: Uri.parse('wss://relay.example'),
      subscriptionId: _subId,
      authorPublicKeyHex: _authorPubkey,
      limit: 20,
      timeout: const Duration(milliseconds: 200),
    );

    expect(events, isEmpty);
  });

  test('uses timeout as an overall OK wait deadline', () async {
    final channel = _FakeWebSocketChannel();
    Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (timer.tick >= 20 || channel.isClosed) {
        timer.cancel();
        return;
      }
      channel.addIncoming('["NOTICE","still not an OK"]');
    });
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    await expectLater(
      datasource.publish(
        relayUri: Uri.parse('wss://relay.example'),
        eventMessage: '["EVENT",{}]',
        eventId: _eventId,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('does not let close failure mask an accepted relay OK', () async {
    final channel = _FakeWebSocketChannel(closeError: StateError('close leak'));
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    Future<void>.microtask(
      () => channel.addIncoming('["OK","$_eventId",true,""]'),
    );

    final accepted = await datasource.publish(
      relayUri: Uri.parse('wss://relay.example'),
      eventMessage: '["EVENT",{}]',
      eventId: _eventId,
      timeout: const Duration(milliseconds: 50),
    );

    expect(accepted, isTrue);
  });

  test('uses timeout as an overall manifest fetch deadline', () async {
    final channel = _FakeWebSocketChannel();
    Timer.periodic(const Duration(milliseconds: 1), (timer) {
      if (timer.tick >= 20 || channel.isClosed) {
        timer.cancel();
        return;
      }
      channel.addIncoming('["NOTICE","still not an EOSE"]');
    });
    final datasource = KeychainManifestNostrRelayDatasource(
      connect: (_) => channel,
    );

    final events = await datasource.fetchManifestEvents(
      relayUri: Uri.parse('wss://relay.example'),
      subscriptionId: 'manifest-sub',
      authorPublicKeyHex: _eventId,
      limit: 20,
      timeout: const Duration(milliseconds: 10),
    );

    expect(events, isEmpty);
    expect(channel.isClosed, isTrue);
  });
}

const _eventId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _subId = 'manifest-sub';
const _secretKey =
    '0000000000000000000000000000000000000000000000000000000000000001';
// The datasource routes returned events by subscription id, not author, so the
// author filter value is irrelevant to what these tests observe.
const _authorPubkey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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
