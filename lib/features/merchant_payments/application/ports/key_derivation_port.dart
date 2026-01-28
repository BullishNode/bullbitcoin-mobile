/// Port (interface) for merchant key derivation service.
///
/// Defines the contract for deriving cryptographic keys from the wallet's
/// master mnemonic using BIP85. This follows the recoverbull pattern for
/// deterministic key generation.
abstract class KeyDerivationPort {
  /// Derives a PGP keypair from the master seed.
  ///
  /// Uses BIP85 path: m/83696968'/828365'/{bits}'/2026'/
  /// where bits is typically 2048 or 4096 for RSA key size.
  ///
  /// Returns a map containing:
  /// - 'privateKey': PEM-encoded private key
  /// - 'publicKey': PEM-encoded public key
  Future<Map<String, String>> derivePgpKeypair({
    required String xprv,
    required int bits,
  });

  /// Derives an AES-256 key from the master seed.
  ///
  /// Uses BIP85 path: m/83696968'/128169'/256'/2026'/{index}'
  /// Returns 32 bytes (256 bits) of entropy for AES-256-GCM.
  ///
  /// The [index] parameter allows deriving multiple AES keys sequentially.
  Future<List<int>> deriveAesKey({
    required String xprv,
    required int index,
  });

  /// Derives a server password from the master seed.
  ///
  /// Uses BIP85 path: m/83696968'/707764'/21'/2026'/
  /// Returns a 21-character Base64 encoded string (~120 bits of entropy).
  ///
  /// This password is used for merchant authentication with the BullPOS backend.
  Future<String> deriveServerPassword({
    required String xprv,
  });
}
