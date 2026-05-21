import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';

String paymentPageErrorMessage(PaymentPageApplicationError error) {
  return switch (error) {
    PaymentPageValidationError(:final message) => _paymentPageValidationMessage(
      message,
    ),
    PaymentPageNotFoundError() => 'Payment page not found.',
    PaymentPageAuthorizationError() => 'Payment page authorization failed.',
    PaymentPageNetworkError() => 'Network error. Check your connection.',
    PaymentPageIdentityUnavailableError() =>
      'Set up a Liquid wallet before editing your payment page.',
    PaymentPageUnexpectedError() => 'Something went wrong. Please try again.',
  };
}

String _paymentPageValidationMessage(String message) {
  if (message.startsWith('Image dimensions are too large.')) {
    return 'Choose a JPEG, PNG, or WebP image under 2 MB.';
  }
  return switch (message) {
    'nym must be 3-32 lowercase letters, numbers, or hyphens' =>
      'Choose a 3-32 character Bullnym name using lowercase letters, numbers, or hyphens.',
    'must be between 1 and 80 bytes' ||
    'header must be 1..=80 chars' => 'Add a title.',
    'must be between 1 and 280 bytes' ||
    'description must be 1..=280 chars' => 'Add a description.',
    'display currency must be one of USD, EUR, CAD, COP, CRC, MXN, ARS' =>
      'Choose a supported display currency.',
    'display_currency is not supported; fetch /api/v1/supported-currencies' =>
      'Choose a supported display currency.',
    'display_currency must be a canonical uppercase ISO 4217 code' =>
      'Choose a supported display currency.',
    'must start with https:// and be at most 200 bytes' =>
      'Website must start with https://.',
    'website must start with https://' => 'Website must start with https://.',
    'image file is empty' => 'Choose a JPEG, PNG, or WebP image under 2 MB.',
    'image file is larger than 2 MB' =>
      'Choose a JPEG, PNG, or WebP image under 2 MB.',
    'image file must be JPEG, PNG, or WebP' =>
      'Choose a JPEG, PNG, or WebP image under 2 MB.',
    'Image was rejected. Use a JPEG, PNG, or WebP file under 2 MB.' =>
      'Choose a JPEG, PNG, or WebP image under 2 MB.',
    'Upload form was malformed. Retry from the app.' =>
      'Choose a JPEG, PNG, or WebP image under 2 MB.',
    'must be 1-50 alphanumeric or underscore characters' =>
      'Twitter can only use letters, numbers, and underscores.',
    'must be 1-50 alphanumeric, dot, or underscore characters' =>
      'Instagram can only use letters, numbers, dots, and underscores.',
    _ => 'Check the payment page details and try again.',
  };
}
