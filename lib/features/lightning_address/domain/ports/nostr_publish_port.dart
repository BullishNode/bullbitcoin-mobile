abstract class NostrPublishPort {
  Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  });

  Future<void> clearProfile({required String privateKeyHex});
}
