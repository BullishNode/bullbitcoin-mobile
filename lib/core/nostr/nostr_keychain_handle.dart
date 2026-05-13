import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:nostr/nostr.dart' show Keys, Schnorr;

/// BIP85 application number for Nostr key derivation (NIP-06).
const int nostrBip85Application = 86;

/// In-memory handle for a Nostr signing key.
///
/// Keep this type inside core/nostr and pass public strings or signatures
/// across feature boundaries. Do not store it in DTOs or persistence models.
final class NostrKeychainHandle {
  final Keys _keys;

  NostrKeychainHandle._(this._keys);

  factory NostrKeychainHandle.fromSecretKeyHex(String secretKeyHex) {
    return NostrKeychainHandle._(Keys(secretKeyHex));
  }

  factory NostrKeychainHandle.deriveFromBip85({
    required String xprvBase58,
    required int identity,
    required int account,
  }) {
    final path = bip85.Bip85HardenedPath(
      "$nostrBip85Application'/$identity'/$account'",
    );
    final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
      xprvBase58: xprvBase58,
      path: path,
    );
    return NostrKeychainHandle.fromSecretKeyHex(entropyHex.substring(0, 64));
  }

  String get publicKeyHex => _keys.public;

  String signHashHex(String messageHashHex, {String? auxHex}) {
    return Schnorr.sign(
      secretKey: _keys.secret,
      message: messageHashHex,
      aux: auxHex,
    );
  }

  String signMessage(List<int> message) {
    final messageHash = sha256.convert(message).bytes;
    return signHashHex(hex.encode(messageHash));
  }

  T withSecretKeyHex<T>(T Function(String secretKeyHex) fn) {
    return fn(_keys.secret);
  }

  @override
  String toString() => 'NostrKeychainHandle(publicKeyHex: $publicKeyHex)';
}
