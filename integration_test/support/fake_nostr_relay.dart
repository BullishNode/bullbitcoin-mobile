import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A stateful in-process NIP-01 relay for L1 tests (HARNESS §2.1). It models
/// NIP-33 replaceable semantics (newer `created_at` replaces the same
/// `(author, kind, d)`), replays matching stored events for a REQ, and captures
/// every inbound EVENT frame verbatim for the wire-format assertions. Hostile
/// modes drive the robustness matrix (ISS-T-06). Fake relays only (G3).
/// Thrown by [FakeNostrRelay.connect] when the relay is toggled offline, so the
/// datasource sees an unreachable socket rather than an empty result.
class SocketConnectException implements Exception {
  const SocketConnectException(this.message);
  final String message;
  @override
  String toString() => 'SocketConnectException: $message';
}

class FakeNostrRelay {
  final List<String> capturedEventFrames = [];
  final Map<String, Map<String, dynamic>> _store = {};

  // Hostile toggles.
  bool neverOk = false;
  bool dropAfterConnect = false;
  Duration? eoseDelay;
  int floodCount = 0;
  int? oversizeContentBytes;
  bool tamperStoredContent = false;
  Map<String, dynamic>? forgedEvent;

  /// E12 (network-toggle, GETPAID-APP-E2E-FAILURE-MATRIX §7.2): when true,
  /// [connect] throws as if the socket could not be opened at all. Unlike
  /// [dropAfterConnect] (which opens then closes, so the datasource still
  /// counts the relay as contacted and reports `noManifestFound`), a connect
  /// failure leaves the relay UNcontacted, which is what makes the fetch report
  /// `relaysUnavailable` — the distinct "unreachable ≠ absent" outcome (P2).
  bool offline = false;

  int get storedEventCount => _store.length;

  WebSocketChannel connect(Uri uri) {
    if (offline) {
      throw const SocketConnectException('fake relay is offline');
    }
    return _FakeRelayChannel(this);
  }

  void _handleFrame(String frame, void Function(String) respond) {
    final Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } catch (_) {
      return;
    }
    if (decoded is! List || decoded.isEmpty) return;
    final type = decoded[0];
    if (type == 'EVENT') {
      capturedEventFrames.add(frame);
      final eventMap = decoded[1];
      if (eventMap is Map<String, dynamic>) {
        _storeEvent(eventMap);
        if (!neverOk) {
          respond(jsonEncode(['OK', eventMap['id'], true, '']));
        }
      }
    } else if (type == 'REQ') {
      final subscriptionId = decoded[1] as String;
      final filter = decoded.length > 2 && decoded[2] is Map
          ? (decoded[2] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      _replay(subscriptionId, filter, respond);
    }
    // CLOSE and everything else: ignore.
  }

  void _storeEvent(Map<String, dynamic> event) {
    final key = _keyOf(event);
    final existing = _store[key];
    final createdAt = event['created_at'] as int? ?? 0;
    if (existing == null || (existing['created_at'] as int? ?? 0) < createdAt) {
      _store[key] = event;
    }
  }

  void _replay(
    String subscriptionId,
    Map<String, dynamic> filter,
    void Function(String) respond,
  ) {
    final authors = (filter['authors'] as List?)?.cast<Object?>();
    final kinds = (filter['kinds'] as List?)?.cast<Object?>();
    final dTags = (filter['#d'] as List?)?.cast<Object?>();
    final limit = filter['limit'] as int? ?? 1 << 30;

    final matches = _store.values.where((event) {
      if (authors != null && !authors.contains(event['pubkey'])) return false;
      if (kinds != null && !kinds.contains(event['kind'])) return false;
      if (dTags != null && !dTags.contains(_dTagOf(event))) return false;
      return true;
    }).toList();

    final forged = forgedEvent;
    if (forged != null) matches.add(forged);

    var emitted = 0;
    for (final event in matches) {
      if (emitted >= limit && floodCount == 0) break;
      respond(jsonEncode(['EVENT', subscriptionId, _project(event)]));
      emitted++;
    }
    // Flood beyond the fetch limit to exercise the datasource bound.
    for (var i = 0; i < floodCount; i++) {
      final base = matches.isNotEmpty ? matches.first : forged;
      if (base == null) break;
      respond(jsonEncode(['EVENT', subscriptionId, _project(base)]));
    }

    void sendEose() => respond(jsonEncode(['EOSE', subscriptionId]));
    final delay = eoseDelay;
    if (delay != null) {
      Timer(delay, sendEose);
    } else {
      sendEose();
    }
  }

  Map<String, dynamic> _project(Map<String, dynamic> event) {
    if (!tamperStoredContent && oversizeContentBytes == null) return event;
    final copy = Map<String, dynamic>.of(event);
    if (tamperStoredContent) {
      // Mutate content after signing so the signature no longer verifies.
      copy['content'] = '${copy['content']}tampered';
    }
    if (oversizeContentBytes != null) {
      copy['content'] = 'A' * oversizeContentBytes!;
    }
    return copy;
  }

  String _keyOf(Map<String, dynamic> event) =>
      '${event['pubkey']}|${event['kind']}|${_dTagOf(event)}';

  String _dTagOf(Map<String, dynamic> event) {
    final tags = event['tags'];
    if (tags is List) {
      for (final tag in tags) {
        if (tag is List && tag.length >= 2 && tag[0] == 'd') {
          return tag[1] as String;
        }
      }
    }
    return '';
  }
}

class _FakeRelayChannel
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  _FakeRelayChannel(this._relay) {
    if (_relay.dropAfterConnect) {
      scheduleMicrotask(_incoming.close);
    }
  }

  final FakeNostrRelay _relay;
  final _incoming = StreamController<Object?>();
  late final _FakeRelaySink _sink = _FakeRelaySink(_relay, _incoming);

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

class _FakeRelaySink implements WebSocketSink {
  _FakeRelaySink(this._relay, this._incoming);

  final FakeNostrRelay _relay;
  final StreamController<Object?> _incoming;
  final _done = Completer<void>();
  bool _closed = false;

  @override
  Future<void> get done => _done.future;

  @override
  void add(Object? event) {
    if (_closed || event is! String) return;
    _relay._handleFrame(event, (response) {
      if (!_incoming.isClosed) _incoming.add(response);
    });
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _closed = true;
    if (!_incoming.isClosed) await _incoming.close();
    if (!_done.isCompleted) _done.complete();
  }
}
