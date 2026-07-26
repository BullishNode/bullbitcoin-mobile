abstract interface class NostrKeyMaterializationRecorder {
  Future<void> record({
    required String reservationId,
    required String derivationPath,
    required String publicKeyHex,
    required String parentFingerprint,
  });
}
