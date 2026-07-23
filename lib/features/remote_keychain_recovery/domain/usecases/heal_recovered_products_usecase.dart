import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';

enum RecoveredProductsHealStatus { finished, timedOut }

/// Runs the DG-3 liveness check for the products a restore flagged for
/// reactivation. It is READ-ONLY: recovery never writes to a Bullnym product
/// (UX-1 / master-doc contract #4). All three products delegate to their
/// read-only liveness checks (GET only; live/archived products are silent,
/// missing/lapsed products surface needsReactivation, and unreachable servers
/// degrade loudly). In particular Lightning Address is queried with
/// `allowReregister: false`, so a lapsed-but-known legacy registration is
/// flagged for user-driven reactivation instead of being silently re-registered
/// — the dashboard/product screens own reactivation. Each product is healed
/// independently. Unknown failures never throw; they degrade to the per-product
/// `unreachable`.
final class HealRecoveredProductsUsecase {
  static const _lightningAddressReservationId = 'lightning_address_wallet_seed';
  static const _paymentPageReservationId = 'payment_page_wallet_seed';
  static const _posReservationId = 'pos_wallet_seed';

  final LightningAddressFacade _lightningAddress;
  final PaymentPageFacade _paymentPage;
  final PosFacade _pos;

  const HealRecoveredProductsUsecase(
    this._lightningAddress,
    this._paymentPage,
    this._pos,
  );

  Future<RecoveredProductsHealStatus> execute(
    Set<String> reactivationReservationIds, {
    DateTime? deadline,
  }) async {
    if (reactivationReservationIds.contains(_lightningAddressReservationId)) {
      final timedOut = await _healLightningAddress(deadline);
      if (timedOut) return RecoveredProductsHealStatus.timedOut;
    }

    if (reactivationReservationIds.contains(_paymentPageReservationId)) {
      await _healPaymentPage();
    }

    if (reactivationReservationIds.contains(_posReservationId)) {
      await _healPos();
    }

    return RecoveredProductsHealStatus.finished;
  }

  Future<bool> _healLightningAddress(DateTime? deadline) async {
    try {
      final outcome = await _lightningAddress.ensureRegistrationLive(
        deadline: deadline,
        allowReregister: false,
      );
      if (outcome.liveness == LightningAddressRegistrationLiveness.timedOut) {
        log.warning(
          'Lightning Address recovery heal did not complete: '
          '${outcome.liveness.name}',
        );
        return true;
      }
      if (outcome.liveness ==
              LightningAddressRegistrationLiveness.needsReactivation ||
          outcome.liveness ==
              LightningAddressRegistrationLiveness.unreachable) {
        log.warning(
          'Lightning Address recovery heal did not complete: '
          '${outcome.liveness.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Lightning Address recovery heal failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
    return false;
  }

  Future<void> _healPaymentPage() async {
    try {
      final outcome = await _paymentPage.ensurePageLive();
      if (outcome.liveness == PaymentPageLiveness.needsReactivation ||
          outcome.liveness == PaymentPageLiveness.unreachable) {
        log.warning(
          'Payment Page recovery heal did not complete: '
          '${outcome.liveness.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Payment Page recovery heal failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }

  Future<void> _healPos() async {
    try {
      final outcome = await _pos.ensurePosLive();
      if (outcome.liveness == PosLiveness.needsReactivation ||
          outcome.liveness == PosLiveness.unreachable) {
        log.warning(
          'Point of Sale recovery heal did not complete: '
          '${outcome.liveness.name}',
        );
      }
    } catch (error, stack) {
      log.warning(
        'Point of Sale recovery heal failed',
        error: error.runtimeType,
        trace: stack,
      );
    }
  }
}
