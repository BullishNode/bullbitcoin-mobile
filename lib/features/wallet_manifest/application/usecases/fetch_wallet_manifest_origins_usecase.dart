import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class FetchWalletManifestOriginsUsecase {
  final WalletManifestOriginStore _originStore;

  FetchWalletManifestOriginsUsecase({
    required WalletManifestOriginStore originStore,
  }) : _originStore = originStore;

  Future<List<WalletManifestOrigin>> execute() async {
    try {
      return await _originStore.fetchAll();
    } catch (e) {
      throw WalletManifestOriginReadException(e);
    }
  }
}
