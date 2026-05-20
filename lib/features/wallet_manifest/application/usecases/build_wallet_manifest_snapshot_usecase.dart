import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network_mapper.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_root_fingerprint.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';

class BuildWalletManifestSnapshotUsecase {
  final FetchWalletManifestOriginsUsecase _fetchOrigins;
  final GetWalletsUsecase _getWallets;

  BuildWalletManifestSnapshotUsecase({
    required FetchWalletManifestOriginsUsecase fetchOrigins,
    required GetWalletsUsecase getWallets,
  }) : _fetchOrigins = fetchOrigins,
       _getWallets = getWallets;

  Future<WalletManifestSnapshot> execute({
    DateTime? now,
    String? rootFingerprint,
  }) async {
    final createdAt = _timestamp(now ?? DateTime.now());
    try {
      final normalizedRootFingerprint =
          WalletManifestRootFingerprint.tryNormalize(rootFingerprint);
      final fetchedOrigins = await _fetchOrigins.execute();
      final origins = normalizedRootFingerprint == null
          ? fetchedOrigins
          : fetchedOrigins
                .where(
                  (origin) =>
                      WalletManifestRootFingerprint.tryNormalize(
                        origin.rootFingerprint,
                      ) ==
                      normalizedRootFingerprint,
                )
                .toList();
      if (origins.isEmpty) {
        return WalletManifestSnapshot(createdAt: createdAt, accounts: const []);
      }

      final wallets = await _getWallets.execute(allEnvironments: true);
      final walletById = {for (final wallet in wallets) wallet.id: wallet};
      final accounts = <WalletManifestAccount>[];

      for (final origin in origins) {
        final wallet = walletById[origin.walletId];
        if (wallet == null) {
          log.warning(
            'Skipping stale wallet manifest origin for missing wallet ${origin.walletId}',
          );
          continue;
        }
        final walletNetwork = walletManifestNetworkFromWalletNetwork(
          wallet.network,
        );
        if (walletNetwork != origin.network) {
          throw WalletManifestSnapshotBuildException(
            StateError('Manifest origin network mismatch: ${origin.walletId}'),
          );
        }
        accounts.add(_account(origin: origin, wallet: wallet));
      }

      return WalletManifestSnapshot(
        createdAt: createdAt,
        accounts: accounts,
      ).collapseDuplicates();
    } on WalletManifestException {
      rethrow;
    } catch (e) {
      throw WalletManifestSnapshotBuildException(e);
    }
  }

  WalletManifestAccount _account({
    required WalletManifestOrigin origin,
    required Wallet wallet,
  }) {
    return WalletManifestAccount(
      rootFingerprint: origin.rootFingerprint,
      bip85DerivationPath: origin.bip85DerivationPath,
      network: origin.network,
      name: wallet.label,
      timestamp: origin.updatedAt,
    );
  }

  int _timestamp(DateTime dateTime) => dateTime.millisecondsSinceEpoch ~/ 1000;
}
