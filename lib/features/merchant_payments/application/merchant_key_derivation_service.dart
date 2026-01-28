import 'dart:convert';
import 'dart:typed_data';

import 'package:bb_mobile/features/merchant_payments/application/ports/key_derivation_port.dart';
import 'package:bip85_entropy/bip85_entropy.dart';
import 'package:crypto/crypto.dart';

/// Service for deriving merchant cryptographic keys using BIP85.
///
/// Follows the recoverbull pattern (index 1608) for deterministic key
/// generation from the wallet's master mnemonic. All keys are derived
/// at specific BIP85 paths to ensure compatibility and recoverability.
class MerchantKeyDerivationService implements KeyDerivationPort {
  // BIP85 application number for merchant keys (follows recoverbull pattern)
  static const int _merchantApplication = 83696968;

  // Sub-applications for different key types
  static const int _pgpSubApp = 828365; // PGP keypair derivation
  static const int _aesSubApp = 128169; // AES key derivation
  static const int _passwordSubApp = 707764; // Password derivation

  // Year marker for versioning (allows key rotation if needed)
  static const int _yearMarker = 2026;

  @override
  Future<Map<String, String>> derivePgpKeypair({
    required String xprv,
    required int bits,
  }) async {
    // Path: m/83696968'/828365'/{bits}'/2026'/
    // Using derive() with custom application similar to recoverbull pattern
    final application = CustomApplication.fromNumber(_merchantApplication);
    final path = "$_pgpSubApp'/$bits'/$_yearMarker'";

    // Derive entropy using BIP85
    final entropy = Bip85Entropy.derive(
      xprvBase58: xprv,
      application: application,
      path: path,
    );

    // For now, we return a placeholder implementation since actual PGP
    // key generation requires OpenPGP libraries (not available in Flutter by default).
    // The entropy can be used with libraries like 'openpgp' package once integrated.
    //
    // TODO: Integrate with OpenPGP library to generate actual RSA keypair
    // from this entropy seed.
    final entropyHex = _bytesToHex(entropy);

    return {
      'privateKey': 'PGP_PRIVATE_KEY_FROM_ENTROPY:$entropyHex',
      'publicKey': 'PGP_PUBLIC_KEY_FROM_ENTROPY:$entropyHex',
      'entropy': entropyHex, // Include raw entropy for testing/integration
    };
  }

  @override
  Future<List<int>> deriveAesKey({
    required String xprv,
    required int index,
  }) async {
    // Path: m/83696968'/128169'/256'/2026'/{index}'
    // Using derive() with custom application similar to recoverbull pattern
    final application = CustomApplication.fromNumber(_merchantApplication);
    final path = "$_aesSubApp'/256'/$_yearMarker'/$index'";

    // Derive entropy using BIP85
    final entropy = Bip85Entropy.derive(
      xprvBase58: xprv,
      application: application,
      path: path,
    );

    // Return first 32 bytes for AES-256
    return entropy.sublist(0, 32);
  }

  @override
  Future<String> deriveServerPassword({
    required String xprv,
  }) async {
    // Path: m/83696968'/707764'/21'/2026'/
    // Using derive() with custom application similar to recoverbull pattern
    final application = CustomApplication.fromNumber(_merchantApplication);
    final path = "$_passwordSubApp'/21'/$_yearMarker'";

    // Derive entropy using BIP85
    final entropy = Bip85Entropy.derive(
      xprvBase58: xprv,
      application: application,
      path: path,
    );

    // Take first 16 bytes (128 bits) and encode to Base64
    // This gives us approximately 21-22 characters with good entropy
    final passwordBytes = entropy.sublist(0, 16);
    final base64Password = base64Url.encode(passwordBytes);

    // Remove padding to get exactly 21 characters (128 bits = 21.33 base64 chars)
    // Base64url encoding of 16 bytes gives 22 chars, we'll take first 21
    return base64Password.substring(0, 21);
  }

  /// Helper method to convert bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Verify that a derived path follows the expected format
  static bool verifyDerivationPath(String path, String keyType) {
    final cleanPath = path.replaceAll("m/", "").replaceAll("'", "");
    final parts = cleanPath.split('/');

    if (parts.isEmpty || int.tryParse(parts[0]) != _merchantApplication) {
      return false;
    }

    switch (keyType) {
      case 'pgp':
        return parts.length >= 4 &&
            int.tryParse(parts[1]) == _pgpSubApp &&
            int.tryParse(parts[3]) == _yearMarker;
      case 'aes':
        return parts.length >= 5 &&
            int.tryParse(parts[1]) == _aesSubApp &&
            int.tryParse(parts[2]) == 256 &&
            int.tryParse(parts[3]) == _yearMarker;
      case 'password':
        return parts.length >= 4 &&
            int.tryParse(parts[1]) == _passwordSubApp &&
            int.tryParse(parts[2]) == 21 &&
            int.tryParse(parts[3]) == _yearMarker;
      default:
        return false;
    }
  }
}
