import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';

/// Runs the DG-3 auto-heal for the products a restore flagged for reactivation.
///
/// Lightning Address (101) delegates to its facade's conditional liveness check
/// (silent re-register if lapsed-but-known — never an unconditional prompt).
/// Payment Page (102) has no client surface yet (§13 Q4): it is recovered
/// wallet-only, so there is nothing to heal. Returns null when nothing needs
/// healing. Never throws (an unknown failure degrades to `unreachable`).
class HealRecoveredProductsUsecase {
  static const _lightningAddressReservationId = 'lightning_address_wallet_seed';
  static const _paymentPageReservationId = 'payment_page_wallet_seed';

  final LightningAddressFacade _lightningAddress;

  const HealRecoveredProductsUsecase(this._lightningAddress);

  Future<LightningAddressHealOutcome?> execute(
    Set<String> reactivationReservationIds,
  ) async {
    if (reactivationReservationIds.contains(_lightningAddressReservationId)) {
      try {
        return await _lightningAddress.ensureRegistrationLive();
      } catch (e, stack) {
        log.warning(
          'AUTOHEAL: lightning address heal failed',
          error: e,
          trace: stack,
        );
        return const LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.unreachable,
        );
      }
    }
    if (reactivationReservationIds.contains(_paymentPageReservationId)) {
      log.fine(
        'AUTOHEAL: payment page recovered wallet-only; no client surface to heal',
      );
      return null;
    }
    return null;
  }
}
