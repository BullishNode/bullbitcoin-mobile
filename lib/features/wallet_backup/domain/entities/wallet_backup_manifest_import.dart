final class WalletBackupManifestImport {
  final String payload;
  final String parentFingerprint;
  final String? metadataPayload;

  WalletBackupManifestImport({
    required this.payload,
    required String parentFingerprint,
    this.metadataPayload,
  }) : parentFingerprint = _normalizeFingerprint(parentFingerprint) {
    if (payload.isEmpty) {
      throw ArgumentError.value(
        payload,
        'payload',
        'wallet backup manifest payload is required',
      );
    }
  }
}

String _normalizeFingerprint(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(normalized)) {
    throw ArgumentError.value(
      value,
      'parentFingerprint',
      'parent fingerprint must be 8 hexadecimal characters',
    );
  }
  return normalized;
}
