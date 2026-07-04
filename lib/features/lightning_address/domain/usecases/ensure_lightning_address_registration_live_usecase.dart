import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';

/// DG-3 auto-heal: a conditional server-liveness check with a silent
/// re-register when a lapsed registration is known — NOT an unconditional
/// "re-enable your product" prompt.
///
/// Run on recovery for the bullnym-backed Lightning Address product. It looks
/// the registration up by the seed-derived npub and:
/// - active:true            -> [live] (no prompt, no re-register);
/// - active:false + nym     -> silent re-register -> [reregistered], or a
///                             rejection (e.g. NymTaken) -> [needsReactivation];
/// - NymNotFound             -> [needsReactivation] (the nym is not recoverable
///                             locally — it is not in the frozen manifest);
/// - network/timeout/server  -> [unreachable] (liveness UNKNOWN; never [live]).
class EnsureLightningAddressRegistrationLiveUsecase {
  // Server-provided error code (bullnym passes it through as the rejection
  // code); a genuinely-missing registration is distinguished from an
  // unreachable server so the UI never blind-heals.
  static const _nymNotFoundCode = 'NymNotFound';

  final LookupWalletOwnedLightningAddressRegistrationUsecase _lookup;
  final RegisterWalletOwnedLightningAddressUsecase _register;

  const EnsureLightningAddressRegistrationLiveUsecase({
    required this._lookup,
    required this._register,
  });

  Future<LightningAddressHealOutcome> execute() async {
    final LightningAddressStatus status;
    try {
      status = await _lookup.execute();
    } on LightningAddressException catch (e) {
      if (e.code == _nymNotFoundCode) {
        // Genuinely missing — the nym is unknown locally (not in the manifest);
        // route to re-activation.
        return const LightningAddressHealOutcome(
          liveness: LightningAddressRegistrationLiveness.needsReactivation,
        );
      }
      // Any other lookup failure: liveness UNKNOWN — degrade loudly.
      return const LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.unreachable,
      );
    } catch (_) {
      return const LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.unreachable,
      );
    }

    if (status.active) {
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.live,
        nym: status.nym,
        lightningAddress: status.lightningAddress,
      );
    }

    // Inactive with a known (previous) nym — silent re-register through the
    // full existing path (prepare returns the already-restored wallet + its
    // ctDescriptor, so the registered descriptor is derivation-equal).
    try {
      // Do NOT publish from the heal path: the recovery cubit is the sole
      // recovery-path publisher and suppresses republish after an older-approved
      // restore. Publishing here would clobber a newer unreadable manifest on
      // the relays (the T-NOCLOBBER side channel).
      final registration = await _register.execute(
        nym: status.nym,
        publishBackupSnapshot: false,
      );
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.reregistered,
        nym: registration.registration.nym,
        lightningAddress: registration.registration.lightningAddress,
      );
    } catch (e) {
      // Rejection (e.g. NymTaken) — offer re-activation. Log id-level only; the
      // nym is user-correlatable and stays out of logs.
      log.warning('AUTOHEAL: silent re-register failed', error: e);
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.needsReactivation,
        nym: status.nym,
      );
    }
  }
}
