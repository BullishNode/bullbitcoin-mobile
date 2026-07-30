import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid_settings/domain/get_paid_wallet_behavior.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';

/// Resolves the reserved LA/PP/POS wallets read-only so each product screen can
/// expose its auto-sweep / hide-on-home controls.
///
/// Resolution goes through the MANIFEST reservation (wallet truth), not a label:
/// the manifest records which wallet id was materialized for each product's
/// fixed BIP85 reservation, so a renamed or colliding label can never resolve
/// the wrong wallet (UX-1 doctrine; the owner-reported wrong-wallet class). It
/// never derives or records anything — a product with no manifest entry (or
/// whose wallet is gone) simply has no behavior, and the controls are absent.
class GetGetPaidWalletBehaviorsUsecase {
  final GetWalletsUsecase _getWallets;
  final KeychainManifestFacade _manifest;

  const GetGetPaidWalletBehaviorsUsecase({
    required this._getWallets,
    required this._manifest,
  });

  /// Resolves every existing reserved product wallet, or - when [only] is set -
  /// just that one product (returning an empty list if its wallet is absent).
  Future<List<GetPaidWalletBehavior>> execute({
    GetPaidWalletProduct? only,
  }) async {
    final wallets = await _getWallets.execute();
    // The product wallets are BIP85-derived from the default wallet's seed, so
    // the manifest records them under that wallet's master fingerprint.
    final parentFingerprint = _parentFingerprint(wallets);
    if (parentFingerprint == null) return const [];

    final walletsById = {for (final wallet in wallets) wallet.id: wallet};
    final products = only == null ? GetPaidWalletProduct.values : [only];
    final results = <GetPaidWalletBehavior>[];

    for (final product in products) {
      final wallet = await _resolveProductWallet(
        parentFingerprint: parentFingerprint,
        product: product,
        walletsById: walletsById,
      );
      if (wallet == null) continue;
      results.add(
        GetPaidWalletBehavior(
          product: product,
          walletId: wallet.id,
          hideOnHome: wallet.hideOnHome,
          autoSweepEnabled: wallet.autoSweepEnabled,
        ),
      );
    }

    return results;
  }

  Future<Wallet?> _resolveProductWallet({
    required String parentFingerprint,
    required GetPaidWalletProduct product,
    required Map<String, Wallet> walletsById,
  }) async {
    final manifestWalletIds = await _manifest.reservationWalletIds(
      parentFingerprint: parentFingerprint,
      reservationId: product.reservationId,
    );
    // The manifest is the sole source of the wallet id; a label is never
    // consulted. Only a wallet the manifest actually recorded for this
    // reservation is eligible.
    for (final walletId in manifestWalletIds) {
      final wallet = walletsById[walletId];
      if (wallet != null && wallet.network.isLiquid) return wallet;
    }
    return null;
  }

  String? _parentFingerprint(List<Wallet> wallets) {
    final defaultWallet = wallets
        .where((wallet) => wallet.isDefault)
        .firstOrNull;
    final fingerprint = defaultWallet?.masterFingerprint ?? '';
    return fingerprint.isEmpty ? null : fingerprint;
  }
}
