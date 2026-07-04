import 'package:bb_mobile/features/nostr_relay_policy/domain/nostr_relay_policy_error.dart';

final class NostrRelayUrl {
  final Uri uri;

  NostrRelayUrl(String value) : uri = _parse(value);

  String get url => uri.toString();

  static Uri _parse(String value) {
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.scheme.toLowerCase() != 'wss') {
      throw NostrRelayUrlException('Nostr relay URL must use wss');
    }
    if (uri.host.isEmpty) {
      throw NostrRelayUrlException('Nostr relay URL must include a host');
    }
    if (uri.hasFragment || uri.hasQuery || uri.userInfo.isNotEmpty) {
      throw NostrRelayUrlException(
        'Nostr relay URL must not include user info, query, or fragment',
      );
    }

    return Uri(
      scheme: 'wss',
      host: uri.host.toLowerCase(),
      port: uri.hasPort && uri.port != 443 ? uri.port : null,
      path: uri.path == '/' ? '' : uri.path,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NostrRelayUrl && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'NostrRelayUrl(url: $url)';
}
