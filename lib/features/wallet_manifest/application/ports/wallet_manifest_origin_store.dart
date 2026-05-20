import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';

abstract class WalletManifestOriginStore {
  Future<void> upsert(WalletManifestOrigin origin);
  Future<List<WalletManifestOrigin>> fetchAll();
  Future<void> deleteByWalletId(String walletId);
}
