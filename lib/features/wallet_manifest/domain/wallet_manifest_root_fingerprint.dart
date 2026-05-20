class WalletManifestRootFingerprint {
  static final _pattern = RegExp(r'^[0-9a-fA-F]{8}$');

  const WalletManifestRootFingerprint._();

  static String normalize(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'rootFingerprint',
        'must be 8 hexadecimal characters',
      );
    }
    return normalized;
  }

  static String? tryNormalize(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (!_pattern.hasMatch(normalized)) return null;
    return normalized;
  }
}
