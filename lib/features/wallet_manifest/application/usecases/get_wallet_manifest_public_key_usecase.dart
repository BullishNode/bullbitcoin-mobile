import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:nostr/nostr.dart' show Nip19, Nip19Prefix;

class GetWalletManifestPublicKeyUsecase {
  final DeriveWalletManifestNostrHandleUsecase _deriveHandle;

  const GetWalletManifestPublicKeyUsecase({
    required DeriveWalletManifestNostrHandleUsecase deriveHandle,
  }) : _deriveHandle = deriveHandle;

  Future<String> execute() async {
    final context = await _deriveHandle.execute();
    final publicKeyHex = context.handle.publicKeyHex;
    return Nip19.encode(prefix: Nip19Prefix.npub, data: publicKeyHex);
  }
}
