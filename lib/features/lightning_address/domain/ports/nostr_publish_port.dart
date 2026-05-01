/// PORT: publishing the user's Nostr kind:0 profile event under their npub.
///
/// Pulled out of the application layer so the LA usecases never reach
/// directly into the framework `NostrRelayClient` static. The adapter
/// wraps that static; tests inject a fake.
abstract class NostrPublishPort {
  /// Publish a NIP-05 profile (kind:0) event tying the user's npub to their
  /// Lightning Address. Best-effort: individual relay failures are logged
  /// by the adapter, not thrown.
  Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  });

  /// Publish an empty kind:0 event to clear any prior NIP-05 advertisement
  /// for this npub.
  Future<void> clearProfile({required String privateKeyHex});
}
