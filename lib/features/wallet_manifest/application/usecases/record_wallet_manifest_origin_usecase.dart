import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_origin_store.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class RecordWalletManifestOriginUsecase {
  final WalletManifestOriginStore _originStore;

  RecordWalletManifestOriginUsecase({
    required WalletManifestOriginStore originStore,
  }) : _originStore = originStore;

  Future<void> execute({
    required String walletId,
    required WalletManifestNetwork network,
    required String rootFingerprint,
    required String bip85DerivationPath,
    DateTime? now,
  }) async {
    final path = Bip85DerivationPath.tryParse(bip85DerivationPath);
    if (path == null) {
      throw WalletManifestInvalidOriginException(
        'Unsupported BIP85 derivation path: $bip85DerivationPath',
      );
    }

    try {
      final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      final origin = WalletManifestOrigin(
        walletId: walletId,
        rootFingerprint: rootFingerprint,
        bip85DerivationPath: path,
        network: network,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await _originStore.upsert(origin);
    } on WalletManifestInvalidOriginException {
      rethrow;
    } on ArgumentError catch (e) {
      throw WalletManifestInvalidOriginException(e.message?.toString() ?? '$e');
    } catch (e) {
      throw WalletManifestOriginPersistenceException(e);
    }
  }
}
