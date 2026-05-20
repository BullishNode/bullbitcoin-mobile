import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/shared/get_paid_identity_derivation.dart';

class InvoicesIdentityDatasource implements InvoicesIdentityPort {
  final GetPaidIdentityDerivation _identityDerivation;

  const InvoicesIdentityDatasource({
    required GetPaidIdentityDerivation identityDerivation,
  }) : _identityDerivation = identityDerivation;

  @override
  Future<NostrKeychainHandle> getSigningHandle() async {
    final handle = await _identityDerivation.getSigningHandle();
    if (handle == null) {
      throw const InvoicesIdentityUnavailableError(
        'No default Bitcoin wallet found',
      );
    }
    return handle;
  }
}
