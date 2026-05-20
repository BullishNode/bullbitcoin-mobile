import 'package:bb_mobile/core/nostr/nostr_facade.dart';
import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const secretKeyHex =
      '0000000000000000000000000000000000000000000000000000000000000001';

  test('exposes public key and signs through the keychain handle', () {
    final facade = NostrFacade();
    final handle = NostrKeychainHandle.fromSecretKeyHex(secretKeyHex);

    expect(facade.npubHex(handle), handle.publicKeyHex);
    expect(facade.signMessage(handle, [1, 2, 3]), hasLength(128));
  });
}
