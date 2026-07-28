import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_error.dart';
import 'package:bb_mobile/features/payment_page/domain/payment_page_validation.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/resolve_payment_page_identity_usecase.dart';

/// Claims the wallet's one lifetime nym from inside the Donation Page flow.
///
/// The nym is the same single claim the Lightning Address flow makes — this goes
/// through the exact same wallet-owned registration, so whichever product the
/// user reaches first can make it and the other two then find it. Claiming it
/// makes `nym@domain` live, which the claim step's copy states.
class ClaimPaymentPageNymUsecase {
  final LightningAddressFacade _lightningAddress;

  const ClaimPaymentPageNymUsecase({required this._lightningAddress});

  /// Returns the server-confirmed nym. Throws a [PaymentPageException] whose
  /// kind names the rejection (taken / reserved / invalid) or the transport
  /// failure.
  Future<String> execute({required String nym}) async {
    final normalized = validatePaymentPageNymClaim(nym);
    try {
      final result = await _lightningAddress.registerWalletOwned(
        nym: normalized,
      );
      return result.registration.nym;
    } on WalletOwnedLightningAddressRegistrationException catch (e) {
      // The wrapper is itself a LightningAddressException, so unwrap first: the
      // rejection the user needs to read is on the cause, not the phase.
      throw _mappedClaimFailure(e.cause);
    } on LightningAddressException catch (e) {
      throw _mappedClaimFailure(e);
    } catch (_) {
      throw const PaymentPageException.unexpected();
    }
  }
}

/// Maps a nym-claim rejection onto the Donation Page family, keeping the three
/// field-level rejections distinct from the transport failures.
PaymentPageException _mappedClaimFailure(LightningAddressException error) {
  return switch (error.code) {
    'NameTaken' => const PaymentPageException.nymTaken(),
    'NymReserved' => const PaymentPageException.nymReserved(),
    'NymInvalid' => const PaymentPageException.nymInvalid(),
    _ => switch (error.kind) {
      LightningAddressErrorKind.reservedNym =>
        const PaymentPageException.nymReserved(),
      LightningAddressErrorKind.invalidNym =>
        const PaymentPageException.nymInvalid(),
      _ => paymentPageExceptionFromLightningAddress(error),
    },
  };
}
