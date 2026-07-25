import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';

enum RecoveredProductsHealStatus { finished, timedOut }

final class HealRecoveredProductsUsecase {
  static const _lightningAddressReservationId = 'lightning_address_wallet_seed';
  static const _paymentPageReservationId = 'payment_page_wallet_seed';

  final LightningAddressFacade _lightningAddress;
  final PaymentPageFacade _paymentPage;

  const HealRecoveredProductsUsecase(this._lightningAddress, this._paymentPage);

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

    return RecoveredProductsHealStatus.finished;
  }

  Future<bool> _healLightningAddress(DateTime? deadline) async {
    try {
      final outcome = await _lightningAddress.ensureRegistrationLive(
        deadline: deadline,
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
}
