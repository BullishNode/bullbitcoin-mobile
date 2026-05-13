import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';

String paymentPageErrorMessage(PaymentPageApplicationError error) {
  return switch (error) {
    PaymentPageValidationError() =>
      'Check the payment page details and try again.',
    PaymentPageNotFoundError() => 'Payment page not found.',
    PaymentPageAuthorizationError() => 'Payment page authorization failed.',
    PaymentPageNetworkError() => 'Network error. Check your connection.',
    PaymentPageIdentityUnavailableError() =>
      'Set up a Bitcoin wallet before editing your payment page.',
    PaymentPageUnexpectedError() => 'Something went wrong. Please try again.',
  };
}
