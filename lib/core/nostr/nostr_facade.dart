import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';

class NostrFacade {
  const NostrFacade({NostrRelayClient relayClient = const NostrRelayClient()})
    : _relayClient = relayClient;

  final NostrRelayClient _relayClient;

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

  Future<void> publishProfile({
    required NostrKeychainHandle handle,
    required String name,
    required String nip05,
    required String lud16,
  }) {
    return handle.withSecretKeyHex(
      (secretKeyHex) => _relayClient.publishProfile(
        privateKeyHex: secretKeyHex,
        name: name,
        nip05: nip05,
        lud16: lud16,
      ),
    );
  }

  Future<void> clearProfile({required NostrKeychainHandle handle}) {
    return handle.withSecretKeyHex(
      (secretKeyHex) => _relayClient.clearProfile(privateKeyHex: secretKeyHex),
    );
  }
}
