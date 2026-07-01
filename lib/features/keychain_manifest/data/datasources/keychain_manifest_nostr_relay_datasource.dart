import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef KeychainManifestNostrRelayConnector =
    WebSocketChannel Function(Uri uri);

class KeychainManifestNostrRelayDatasource {
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

  bool _isOkForEvent(Object? message, String eventId) {
    final decoded = _decodeMessage(message);
    return decoded != null &&
        decoded.length >= 4 &&
        decoded[0] == 'OK' &&
        decoded[1] == eventId &&
        decoded[2] is bool;
  }

  bool _isAcceptedOk(Object? message) {
    final decoded = _decodeMessage(message);
    return decoded != null && decoded.length >= 3 && decoded[2] == true;
  }

  List<Object?>? _decodeMessage(Object? message) {
    if (message is! String) return null;
    try {
      final decoded = jsonDecode(message);
      if (decoded is List) return decoded.cast<Object?>();
      return null;
    } catch (_) {
      return null;
    }
  }
}
