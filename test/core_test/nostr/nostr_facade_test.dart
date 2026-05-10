import 'package:bb_mobile/core/nostr/nostr_facade.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/nostr/nostr_relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRelayClient extends NostrRelayClient {
  String? publishedSecretKeyHex;
  String? clearedSecretKeyHex;

  @override
  Future<void> publishProfile({
    required String privateKeyHex,
    required String name,
    required String nip05,
    required String lud16,
  }) async {
    publishedSecretKeyHex = privateKeyHex;
  }

  @override
  Future<void> clearProfile({required String privateKeyHex}) async {
    clearedSecretKeyHex = privateKeyHex;
  }
}

void main() {
  const secretKeyHex =
      '0000000000000000000000000000000000000000000000000000000000000001';

  test('exposes public key and signs through the keychain handle', () {
    final facade = NostrFacade();
    final handle = NostrKeychainHandle.fromSecretKeyHex(secretKeyHex);

    expect(facade.npubHex(handle), handle.publicKeyHex);
    expect(facade.signMessage(handle, [1, 2, 3]), hasLength(128));
  });

  test('relay publishing keeps secret access inside callback scope', () async {
    final relay = _FakeRelayClient();
    final facade = NostrFacade(relayClient: relay);
    final handle = NostrKeychainHandle.fromSecretKeyHex(secretKeyHex);

    await facade.publishProfile(
      handle: handle,
      name: 'alice',
      nip05: 'alice@example.com',
      lud16: 'alice@example.com',
    );
    await facade.clearProfile(handle: handle);

    expect(relay.publishedSecretKeyHex, secretKeyHex);
    expect(relay.clearedSecretKeyHex, secretKeyHex);
  });
}
