import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/get_wallet_manifest_public_key_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nostr/nostr.dart' show Nip19, Nip19Prefix;

class _MockDeriveHandle extends Mock
    implements DeriveWalletManifestNostrHandleUsecase {}

void main() {
  test('returns only the wallet manifest npub', () async {
    final deriveHandle = _MockDeriveHandle();
    final handle = NostrKeychainHandle.fromSecretKeyHex('01' * 32);
    final usecase = GetWalletManifestPublicKeyUsecase(
      deriveHandle: deriveHandle,
    );
    when(() => deriveHandle.execute()).thenAnswer(
      (_) async => WalletManifestNostrHandleContext(
        handle: handle,
        rootFingerprint: 'abcd1234',
      ),
    );

    final npub = await usecase.execute();

    expect(
      npub,
      Nip19.encode(prefix: Nip19Prefix.npub, data: handle.publicKeyHex),
    );
  });
}
