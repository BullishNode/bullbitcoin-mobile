import 'dart:typed_data';

import 'package:bip85_entropy/bip85_entropy.dart' as bip85;
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:crypto/crypto.dart';

/// BIP85 application number for Nostr key derivation (NIP-06).
const int nostrBip85Application = 86;

class NostrIdentity {
  final String npubHex;
  final String _nsecHex;
  final ECPrivate _ecPrivate;

  NostrIdentity._(this.npubHex, this._nsecHex, this._ecPrivate);

  /// Derive a Nostr identity from a master xprv at the given identity/account index.
  /// Path: m/83696968'/{nostrBip85Application}'/{identity}'/{account}'
  static NostrIdentity derive({
    required String xprvBase58,
    required int identity,
    int account = 0,
  }) {
    final path = bip85.Bip85HardenedPath(
      "$nostrBip85Application'/$identity'/$account'",
    );
    final entropyHex = bip85.Bip85Entropy.deriveFromHardenedPath(
      xprvBase58: xprvBase58,
      path: path,
    );

    final nsecHex = entropyHex.substring(0, 64);
    final ecPrivate = ECPrivate.fromHex(nsecHex);
    final npubHex = ecPrivate.getPublic().toXOnlyHex();

    return NostrIdentity._(npubHex, nsecHex, ecPrivate);
  }

  /// Sign a message with BIP-340 schnorr (SHA256 hash then sign).
  String signSchnorr(List<int> message) {
    final messageHash = sha256.convert(message).bytes;
    return _ecPrivate.signBip340(
      Uint8List.fromList(messageHash),
      tweak: false,
    );
  }

  // Scoped access to the private key. Don't retain `nsec` past the callback.
  T withPrivateKeyHex<T>(T Function(String nsec) fn) => fn(_nsecHex);

  @override
  String toString() => 'NostrIdentity(npub: $npubHex)';
}
