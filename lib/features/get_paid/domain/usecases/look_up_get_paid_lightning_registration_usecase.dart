import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';

/// Get Paid's own view of the wallet-owned Lightning Address registration: the
/// identity the hub renders and keys the Donation Page / POS reads on. Carries
/// no Lightning Address protocol detail.
class GetPaidLightningRegistration {
  /// The claimed nym, or null for a CONFIRMED empty account (no nym yet).
  final String? nym;

  /// The published address, or null when none is advertised.
  final String? address;

  /// True when the registration is live on the server. Independent of [address]:
  /// an inactive registration may still carry one.
  final bool active;

  const GetPaidLightningRegistration({
    required this.nym,
    required this.address,
    required this.active,
  });
}

/// Get Paid's narrow wrapper over the Lightning Address boundary. It resolves
/// the wallet-owned registration and normalises the two empty-account shapes the
/// boundary reports — a `NymNotFound` rejection and an empty nym — into a single
/// confirmed-empty registration, so presentation only has to tell "known" from
/// "unknown".
///
/// Returns null when the truth is UNKNOWN (the lookup failed): the nym keys the
/// Donation Page and POS reads, so the hub must leave all three products
/// unavailable rather than guess that they are absent.
class LookUpGetPaidLightningRegistrationUsecase {
  static const _nymNotFoundCode = 'NymNotFound';

  final LightningAddressFacade _lightningAddress;

  const LookUpGetPaidLightningRegistrationUsecase({
    required this._lightningAddress,
  });

  Future<GetPaidLightningRegistration?> execute() async {
    final LightningAddressStatus status;
    try {
      status = await _lightningAddress.lookupWalletOwnedRegistration();
    } on LightningAddressException catch (error, trace) {
      if (error.code != _nymNotFoundCode) {
        return _reportUnavailable(error, trace);
      }
      return const GetPaidLightningRegistration(
        nym: null,
        address: null,
        active: false,
      );
    } on Exception catch (error, trace) {
      return _reportUnavailable(error, trace);
    }

    final address = status.lightningAddress;
    return GetPaidLightningRegistration(
      nym: status.nym.isEmpty ? null : status.nym,
      address: (address?.isEmpty ?? true) ? null : address,
      active: status.active,
    );
  }

  GetPaidLightningRegistration? _reportUnavailable(
    Object error,
    StackTrace trace,
  ) {
    log.warning(
      'Get Paid Lightning Address registration lookup failed',
      error: error,
      trace: trace,
    );
    return null;
  }
}
