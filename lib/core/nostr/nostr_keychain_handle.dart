import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:bech32/bech32.dart';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:convert/convert.dart';

/// BIP85 application number for direct Nostr key derivation.
///
/// Path suffix: `128002'/{identity}'/{account_index}'`.
const int nostrBip85Application = 128002;

/// In-memory handle for a Nostr signing key.
///
/// Do not store this type in DTOs or persistence models. It exposes public-key
/// access and hash signing, but it does not expose raw secret-key material.
final class NostrKeychainHandle {
  final ECPrivate _key;

  NostrKeychainHandle._(this._key);

  factory NostrKeychainHandle._fromSecretKeyHex(String secretKeyHex) {
    return NostrKeychainHandle._(ECPrivate.fromHex(secretKeyHex));
  }

  factory NostrKeychainHandle.deriveFromBip85Path({
    required String xprvBase58,
    required String hardenedPath,
  }) {
    _validateNostrBip85Path(hardenedPath);
    final path = bip85.Bip85HardenedPath(hardenedPath);
    final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
      xprvBase58: xprvBase58,
      path: path,
    );
    return NostrKeychainHandle._fromSecretKeyHex(entropyHex.substring(0, 64));
  }

  String get publicKeyHex => _key.getPublic().toXOnlyHex();

  String signHashHex(String messageHashHex) {
    final digest = hex.decode(messageHashHex);
    if (digest.length != 32) {
      throw ArgumentError.value(
        messageHashHex,
        'messageHashHex',
        'Nostr signing requires a 32-byte hash hex value',
      );
    }
    return _key.signBip340(digest, tweak: false);
  }

  @override
  String toString() => 'NostrKeychainHandle(publicKeyHex: $publicKeyHex)';
}

void _validateNostrBip85Path(String hardenedPath) {
  final match = RegExp(r"^(\d+)'/(\d+)'/(\d+)'$").firstMatch(hardenedPath);
  if (match == null) {
    throw ArgumentError.value(
      hardenedPath,
      'hardenedPath',
      "Expected a Nostr BIP85 path shaped as 128002'/identity'/account'",
    );
  }

  final application = int.parse(match.group(1)!);
  final identity = int.parse(match.group(2)!);
  final account = int.parse(match.group(3)!);
  const maxHardenedChild = 0x7fffffff;
  if (application > maxHardenedChild ||
      identity > maxHardenedChild ||
      account > maxHardenedChild) {
    throw ArgumentError.value(
      hardenedPath,
      'hardenedPath',
      'Nostr BIP85 path components exceed the hardened child range',
    );
  }
  if (application != nostrBip85Application) {
    throw ArgumentError.value(
      hardenedPath,
      'hardenedPath',
      'Expected Nostr BIP85 application $nostrBip85Application',
    );
  }
  if (identity == 0) {
    throw ArgumentError.value(
      hardenedPath,
      'hardenedPath',
      'Nostr identity zero is reserved by BIP85',
    );
  }
  if (account == 0) {
    throw ArgumentError.value(
      hardenedPath,
      'hardenedPath',
      'Nostr account zero is reserved by BIP85',
    );
  }
}

/// Secret materialization is deliberately a one-shot operation. Callers must
/// not persist the returned value or place it in application state.
final class NostrKeychainSecretMaterializer {
  const NostrKeychainSecretMaterializer._();

  static String deriveSecretKeyHex({
    required String xprvBase58,
    required String hardenedPath,
  }) {
    _validateNostrBip85Path(hardenedPath);
    final path = bip85.Bip85HardenedPath(hardenedPath);
    final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
      xprvBase58: xprvBase58,
      path: path,
    );
    return entropyHex.substring(0, 64);
  }

  static String deriveNsec({
    required String xprvBase58,
    required String hardenedPath,
  }) {
    final secretKeyHex = deriveSecretKeyHex(
      xprvBase58: xprvBase58,
      hardenedPath: hardenedPath,
    );
    return bech32.encode(
      Bech32('nsec', _convertBits(hex.decode(secretKeyHex), 8, 5, true)),
    );
  }
}

List<int> _convertBits(List<int> data, int from, int to, bool pad) {
  var accumulator = 0;
  var bits = 0;
  final result = <int>[];
  final maxValue = (1 << to) - 1;
  final maxAccumulator = (1 << (from + to - 1)) - 1;
  for (final value in data) {
    if (value < 0 || value >> from != 0) {
      throw ArgumentError.value(value, 'data');
    }
    accumulator = ((accumulator << from) | value) & maxAccumulator;
    bits += from;
    while (bits >= to) {
      bits -= to;
      result.add((accumulator >> bits) & maxValue);
    }
  }
  if (pad) {
    if (bits > 0) result.add((accumulator << (to - bits)) & maxValue);
  } else if (bits >= from || ((accumulator << (to - bits)) & maxValue) != 0) {
    throw ArgumentError('Invalid bit conversion padding');
  }
  return result;
}
