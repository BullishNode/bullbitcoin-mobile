import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';

class NostrIdentity {
  final NostrKeychainHandle _handle;

  NostrIdentity._(this._handle);

  String get npubHex => _handle.publicKeyHex;

  /// Derive a Nostr identity from a master xprv at the given identity/account index.
  /// Path: m/83696968'/{nostrBip85Application}'/{identity}'/{account_index}'
  static NostrIdentity derive({
    required String xprvBase58,
    required int identity,
    required int account,
  }) {
    final handle = NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprvBase58,
      identity: identity,
      account: account,
    );
    return NostrIdentity._(handle);
  }

  /// Sign a message with BIP-340 schnorr (SHA256 hash then sign).
  String signSchnorr(List<int> message) {
    return _handle.signMessage(message);
  }

  // Scoped access to the private key. Don't retain `nsec` past the callback.
  T withPrivateKeyHex<T>(T Function(String nsec) fn) {
    return _handle.withSecretKeyHex(fn);
  }

  @override
  String toString() => 'NostrIdentity(npub: $npubHex)';
}
