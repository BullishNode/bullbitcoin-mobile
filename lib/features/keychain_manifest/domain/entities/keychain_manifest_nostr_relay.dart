import 'package:bb_mobile/features/keychain_manifest/domain/keychain_manifest_error.dart';

final class KeychainManifestNostrRelayUrl {
  final Uri uri;

  KeychainManifestNostrRelayUrl(String value) : uri = _parse(value);

  String get value => uri.toString();

  static Uri _parse(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw KeychainManifestInvalidEntryException(
        'keychain manifest Nostr relay URL is required',
      );
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        uri.scheme != 'wss' ||
        uri.host.isEmpty) {
      throw KeychainManifestInvalidEntryException(
        'keychain manifest Nostr relay URL must be a wss URL',
      );
    }
    return uri;
  }

  @override
  bool operator ==(Object other) =>
      other is KeychainManifestNostrRelayUrl && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
