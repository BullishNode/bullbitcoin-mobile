import 'dart:async';

import 'package:bb_mobile/features/keychain_manifest/data/datasources/keychain_manifest_nostr_relay_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
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
}

const _eventId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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
