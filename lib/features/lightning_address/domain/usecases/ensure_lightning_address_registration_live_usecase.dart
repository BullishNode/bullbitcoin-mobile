import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_error.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration.dart';
import 'package:bb_mobile/features/lightning_address/domain/lightning_address_registration_liveness.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';

/// DG-3 server-liveness check.
///
/// Run on recovery for the bullnym-backed Lightning Address product. It looks
/// the registration up by the seed-derived npub and:
/// - active:true            -> [live] (no prompt, no re-register);
/// - permanent name + offline -> [needsReactivation] without a write, because
///                                offline is an intentional product state;
/// - active:false + nym     -> silent re-register -> [reregistered], or a
///                             rejection -> [needsReactivation] for legacy
///                             servers only;
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

    // Under permanent_names_v1, inactive means the Lightning Address product
    // is deliberately offline; ownership remains on the server. Recovery must
    // reconstruct that state and wait for an explicit user action, never turn
    // the product back on as a side effect of restoring local wallet data.
    final permanentName = status.permanentNameStatus;
    if (permanentName != null) {
      return LightningAddressHealOutcome(
        liveness: LightningAddressRegistrationLiveness.needsReactivation,
        nym: permanentName.nym,
      );
    }

    // Preserve the existing legacy-server recovery behavior. Permanent-name
    // servers never enter this path because the typed lookup status above is
    // present only for the exact permanent_names_v1 policy.
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
