import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class DeleteWalletManifestOriginUsecase {
  final WalletManifestOriginStore _originStore;

  const DeleteWalletManifestOriginUsecase({
    required WalletManifestOriginStore originStore,
  }) : _originStore = originStore;

  Future<void> execute({required String walletId}) async {
    try {
      await _originStore.deleteByWalletId(walletId);
    } catch (e) {
      throw WalletManifestOriginPersistenceException(e);
    }
  }
}
