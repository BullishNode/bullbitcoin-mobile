import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';

/// The Get Paid products with a fixed-derivation (BIP85) wallet the dashboard
/// can self-heal: Lightning Address (101), Donation Page (102), POS (103).
enum GetPaidWalletBackedProduct { lightningAddress, paymentPage, pos }

/// Outcome of ensuring a product's fixed-path wallet is present locally.
enum GetPaidProductWalletOutcome {
  /// The wallet already existed locally — an idempotent no-op.
  present,

  /// The wallet was missing and has just been re-derived + recorded.
  rederived,

  /// Re-derivation failed; the product must surface a missing-wallet warning
  /// and disable its wallet-dependent controls.
  failed,
}

/// Contract #4 Q9/Q9b self-heal. When a Get Paid product is ACTIVE on the
/// server but its fixed-derivation wallet is missing locally, re-derive that
/// wallet from the product's fixed BIP85 path and record it in the manifest —
/// the ONLY permitted product-triggered wallet creation.
///
/// It reuses each product's existing idempotent `prepareWallet()` (no second
/// derivation path): a present wallet returns `created: false` (no-op, no
/// backup churn), a missing wallet is re-derived and recorded. Any failure is
/// swallowed into [GetPaidProductWalletOutcome.failed] so the dashboard can
/// show a warning without breaking the rest of the hub.
class EnsureGetPaidProductWalletUsecase {
  final LightningAddressFacade _lightningAddress;
  final PaymentPageFacade _paymentPage;
  final PosFacade _pos;

  const EnsureGetPaidProductWalletUsecase(
    this._lightningAddress,
    this._paymentPage,
    this._pos,
  );

  Future<GetPaidProductWalletOutcome> execute(
    GetPaidWalletBackedProduct product,
  ) async {
    try {
      final created = switch (product) {
        GetPaidWalletBackedProduct.lightningAddress =>
          (await _lightningAddress.prepareWallet()).created,
        GetPaidWalletBackedProduct.paymentPage =>
          (await _paymentPage.prepareWallet()).created,
        GetPaidWalletBackedProduct.pos => (await _pos.prepareWallet()).created,
      };
      return created
          ? GetPaidProductWalletOutcome.rederived
          : GetPaidProductWalletOutcome.present;
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid product wallet self-heal failed for ${product.name}',
        error: error,
        trace: trace,
      );
      return GetPaidProductWalletOutcome.failed;
    }
  }
}
