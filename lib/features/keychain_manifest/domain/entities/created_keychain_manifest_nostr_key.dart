/// Result of creating a user-managed Nostr identity.
final class CreatedKeychainManifestNostrKey {
  final String parentFingerprint;
  final String derivationPath;
  final String publicKeyHex;
  final String purpose;
  final String? description;

  const CreatedKeychainManifestNostrKey({
    required this.parentFingerprint,
    required this.derivationPath,
    required this.publicKeyHex,
    required this.purpose,
    this.description,
  });
}
