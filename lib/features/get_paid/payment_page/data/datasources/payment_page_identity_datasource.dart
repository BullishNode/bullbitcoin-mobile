import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/ports/payment_page_identity_port.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_identity_derivation.dart';

class PaymentPageIdentityDatasource implements PaymentPageIdentityPort {
  final GetPaidIdentityDerivation _identityDerivation;

  const PaymentPageIdentityDatasource({
    required GetPaidIdentityDerivation identityDerivation,
  }) : _identityDerivation = identityDerivation;

  @override
  Future<NostrKeychainHandle> getSigningHandle() async {
    final handle = await _identityDerivation.getSigningHandle();
    if (handle == null) {
      throw const PaymentPageIdentityUnavailableError(
        'No default Bitcoin wallet found',
      );
    }
    return handle;
  }
}
