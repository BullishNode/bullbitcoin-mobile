import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;

final class WalletBackupWallet {
  final String xprvBase58;
  final String parentFingerprint;

  WalletBackupWallet({
    required String xprvBase58,
    required String parentFingerprint,
  }) : xprvBase58 = xprvBase58.trim(),
       parentFingerprint = parentFingerprint.trim().toLowerCase() {
    if (this.xprvBase58.isEmpty) {
      throw ArgumentError.value(
        xprvBase58,
        'xprvBase58',
        'wallet backup extended private key must not be empty',
      );
    }
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(this.parentFingerprint)) {
      throw ArgumentError.value(
        parentFingerprint,
        'parentFingerprint',
        'wallet backup parent fingerprint must be 4-byte hexadecimal',
      );
    }
    final String actualFingerprint;
    try {
      actualFingerprint = bip32.Bip32Keys.fromBase58(
        this.xprvBase58,
      ).fingerprintHex;
    } on FormatException catch (error) {
      throw ArgumentError.value(
        xprvBase58,
        'xprvBase58',
        'wallet backup extended private key is malformed: '
            '${error.runtimeType}',
      );
    } on ArgumentError catch (error) {
      throw ArgumentError.value(
        xprvBase58,
        'xprvBase58',
        'wallet backup extended private key is invalid: ${error.runtimeType}',
      );
    }
    if (actualFingerprint != this.parentFingerprint) {
      throw ArgumentError(
        'wallet backup extended private key does not match its parent '
        'fingerprint',
      );
    }
  }
}
