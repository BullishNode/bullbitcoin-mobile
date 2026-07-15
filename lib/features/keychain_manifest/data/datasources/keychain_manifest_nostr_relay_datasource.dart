import 'package:nostr/nostr.dart' as nostr;
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
    final result = _commandResult(message);
    return result != null && result.eventId == eventId;
  }

  bool _isAcceptedOk(Object? message) {
    return _commandResult(message)?.status == true;
  }

  nostr.Nip20? _commandResult(Object? message) {
    if (message is! String) return null;
    try {
      final decoded = nostr.Message.deserialize(message);
      if (decoded.messageType != nostr.MessageType.ok) return null;
      final result = decoded.message;
      if (result is nostr.Nip20) return result;
      return null;
    } catch (_) {
      return null;
    }
  }
}
