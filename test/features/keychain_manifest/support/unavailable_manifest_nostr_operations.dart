import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';

/// Explicit fake capabilities for tests that exercise only manifest inventory
/// and file serialization. Production always supplies real Nostr operations.
abstract final class UnavailableManifestNostrOperations {
  static Future<bool> record(
    KeychainManifestNostrKeyRequest request, {
    DateTime? now,
    DateTime? updatedAt,
  }) => throw UnsupportedError('Nostr operations are outside this test');

  static Future<List<KeychainManifestNostrKeyRecord>> get(
    String parentFingerprint,
  ) => throw UnsupportedError('Nostr operations are outside this test');

  static Future<List<KeychainManifestNostrKeyRecord>> getDefault() =>
      throw UnsupportedError('Nostr operations are outside this test');

  static Future<void> update({
    required String parentFingerprint,
    required String entryId,
    String? purpose,
    String? description,
    DateTime? now,
  }) => throw UnsupportedError('Nostr operations are outside this test');

  static Future<CreatedKeychainManifestNostrKey> create({
    required String purpose,
    String? description,
    DateTime? now,
  }) => throw UnsupportedError('Nostr operations are outside this test');
}
