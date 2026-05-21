import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';

String invoiceErrorMessage(InvoicesApplicationError error) {
  return switch (error) {
    InvoicesValidationError(:final message) =>
      message.isEmpty ? 'Check the invoice details and try again.' : message,
    InvoicesNotFoundError() => 'Invoice not found.',
    InvoicesAuthorizationError() => 'Invoice authorization failed.',
    InvoicesRateLimitedError() => 'Too many attempts. Try again later.',
    InvoicesNetworkError() => 'Network error. Check your connection.',
    InvoicesNoDefaultBitcoinWalletError() =>
      'Set up a default Bitcoin wallet first.',
    InvoicesNoDefaultLiquidWalletError() =>
      'Set up a default Liquid wallet first.',
    InvoicesBitcoinAddressAlreadyUsedError() =>
      'A fresh Bitcoin receive address is required. Try again.',
    InvoicesLiquidAddressAlreadyUsedError() =>
      'A fresh Liquid receive address is required. Try again.',
    InvoicesIdentityUnavailableError() =>
      'Get Paid identity is unavailable. Check your default wallet.',
    InvoicesUnexpectedError() => 'Something went wrong. Please try again.',
  };
}
