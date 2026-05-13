import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';

class NostrFacade {
  const NostrFacade();

  NostrKeychainHandle deriveFromBip85({
    required String xprvBase58,
    required int identity,
    required int account,
  }) {
    return NostrKeychainHandle.deriveFromBip85(
      xprvBase58: xprvBase58,
      identity: identity,
      account: account,
    );
  }

  String npubHex(NostrKeychainHandle handle) {
    return handle.publicKeyHex;
  }

  String signMessage(NostrKeychainHandle handle, List<int> message) {
    return handle.signMessage(message);
  }
}
