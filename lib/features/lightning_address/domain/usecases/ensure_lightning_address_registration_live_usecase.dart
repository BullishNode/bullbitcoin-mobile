import 'dart:async';

import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';

final class EnsureLightningAddressRegistrationLiveUsecase {
  static const _nymNotFoundCode = 'NymNotFound';

  final LookupWalletOwnedLightningAddressRegistrationUsecase _lookup;
  final RegisterWalletOwnedLightningAddressUsecase _register;

  const EnsureLightningAddressRegistrationLiveUsecase(
    this._lookup,
    this._register,
  );

  Future<LightningAddressHealOutcome> execute({DateTime? deadline}) async {
    if (_deadlineReached(deadline)) return _timedOut;

    final LightningAddressStatus status;
    try {
      final lookup = _lookup.execute();
      status = deadline == null
          ? await lookup
          : await lookup.timeout(_remaining(deadline));
    } on TimeoutException {
      return _timedOut;
    } on LightningAddressException catch (error) {
      return LightningAddressHealOutcome(
        liveness: error.code == _nymNotFoundCode
            ? LightningAddressRegistrationLiveness.needsReactivation
            : LightningAddressRegistrationLiveness.unreachable,
      );
    } catch (_) {
      return const LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.unreachable,
      );
    }
    if (_deadlineReached(deadline)) return _timedOut;

    if (status.active) {
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.live,
        nym: status.nym,
        lightningAddress: status.lightningAddress,
      );
    }

    try {
      final registrationRequest = _register.executeFromRecovery(
        nym: status.nym,
      );
      final registration = deadline == null
          ? await registrationRequest
          : await registrationRequest.timeout(_remaining(deadline));
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.reregistered,
        nym: registration.registration.nym,
        lightningAddress: registration.registration.lightningAddress,
      );
    } on TimeoutException {
      return _timedOut;
    } catch (error, stack) {
      log.warning(
        'Lightning Address silent re-registration failed',
        error: error.runtimeType,
        trace: stack,
      );
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.needsReactivation,
        nym: status.nym,
      );
    }
  }

  bool _deadlineReached(DateTime? deadline) {
    return deadline != null && !DateTime.now().isBefore(deadline);
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static const _timedOut = LightningAddressHealOutcome(
    liveness: LightningAddressRegistrationLiveness.timedOut,
  );
}
