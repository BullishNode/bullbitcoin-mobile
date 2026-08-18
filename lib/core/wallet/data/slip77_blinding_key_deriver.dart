import 'package:bech32/bech32.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hex/hex.dart';

/// Compatibility implementation of the SLIP-77 operation used by LWK.
///
/// The application deliberately preserves its pinned Bull SDK. That SDK
/// exposes the wallet's SLIP-77 master key and each address's public blinding
/// key, but not the newer combined address-and-secret operation. This class
/// derives the per-address secret without changing the SDK pin; the caller
/// must verify its public key against the one returned with the address.
final class Slip77BlindingKeyDeriver {
  const Slip77BlindingKeyDeriver();

  Future<String> derive({
    required String masterKeyExpression,
    required String standardAddress,
  }) async {
    final match = RegExp(
      r'^slip77\(([0-9a-fA-F]{64})\)$',
    ).firstMatch(masterKeyExpression);
    if (match == null) {
      throw const FormatException('Unsupported Liquid blinding key type');
    }

    final scriptPubKey = _scriptPubKey(standardAddress);
    final masterKeyBytes = HEX.decode(match.group(1)!);
    final masterKey = SecretKeyData(
      masterKeyBytes,
      overwriteWhenDestroyed: true,
    );
    try {
      final derived = await Hmac.sha256().calculateMac(
        scriptPubKey,
        secretKey: masterKey,
      );
      return HEX.encode(derived.bytes);
    } finally {
      masterKey.destroy();
      masterKeyBytes.fillRange(0, masterKeyBytes.length, 0);
    }
  }

  List<int> _scriptPubKey(String standardAddress) {
    final decoded = bech32.decode(standardAddress);
    if (decoded.hrp != 'ex' && decoded.hrp != 'tex' && decoded.hrp != 'ert') {
      throw const FormatException('Unsupported Liquid address network');
    }
    if (decoded.data.isEmpty || decoded.data.first != 0) {
      throw const FormatException('Expected a version-0 Liquid address');
    }

    final witnessProgram = _convertBits(
      decoded.data.sublist(1),
      fromBits: 5,
      toBits: 8,
      pad: false,
    );
    if (witnessProgram.length != 20) {
      throw const FormatException('Expected a Liquid P2WPKH address');
    }
    return [0, witnessProgram.length, ...witnessProgram];
  }

  List<int> _convertBits(
    List<int> input, {
    required int fromBits,
    required int toBits,
    required bool pad,
  }) {
    var accumulator = 0;
    var bits = 0;
    final output = <int>[];
    final maxValue = (1 << toBits) - 1;
    final maxAccumulator = (1 << (fromBits + toBits - 1)) - 1;

    for (final value in input) {
      if (value < 0 || value >> fromBits != 0) {
        throw const FormatException('Invalid Liquid address data');
      }
      accumulator = ((accumulator << fromBits) | value) & maxAccumulator;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        output.add((accumulator >> bits) & maxValue);
      }
    }

    if (pad) {
      if (bits > 0) output.add((accumulator << (toBits - bits)) & maxValue);
    } else if (bits >= fromBits ||
        ((accumulator << (toBits - bits)) & maxValue) != 0) {
      throw const FormatException('Invalid Liquid address padding');
    }
    return output;
  }
}
