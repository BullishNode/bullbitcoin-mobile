import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';

enum RecoveredProductsHealStatus { finished, timedOut }

final class HealRecoveredProductsUsecase {
  static const _lightningAddressReservationId = 'lightning_address_wallet_seed';

  final LightningAddressFacade _lightningAddress;

  const HealRecoveredProductsUsecase(this._lightningAddress);

  Future<RecoveredProductsHealStatus> execute(
    Set<String> reactivationReservationIds, {
    DateTime? deadline,
  }) async {
    if (!reactivationReservationIds.contains(_lightningAddressReservationId)) {
      return RecoveredProductsHealStatus.finished;
    }

    try {
      final outcome = await _lightningAddress.ensureRegistrationLive(
        deadline: deadline,
      );
      if (outcome.liveness == LightningAddressRegistrationLiveness.timedOut) {
        log.warning(
          'Lightning Address recovery heal did not complete: '
          '${outcome.liveness.name}',
        );
        return RecoveredProductsHealStatus.timedOut;
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
    return RecoveredProductsHealStatus.finished;
  }
}
