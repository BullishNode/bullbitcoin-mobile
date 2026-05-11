import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/payment_page_constants.dart';

class SavePaymentPageCommand {
  static final _twitterHandleRegex = RegExp(r'^[A-Za-z0-9_]{1,50}$');
  static final _instagramHandleRegex = RegExp(r'^[A-Za-z0-9._]{1,50}$');

  final String nym;
  final String header;
  final String description;
  final String displayCurrency;
  final String? website;
  final String? twitter;
  final String? instagram;
  final bool enabled;

  SavePaymentPageCommand({
    required this.nym,
    required this.header,
    required this.description,
    required this.displayCurrency,
    this.website,
    this.twitter,
    this.instagram,
    required this.enabled,
  }) {
    _validate();
  }

  void _validate() {
    if (!paymentPageNymRegex.hasMatch(nym)) {
      throw const PaymentPageValidationError(
        'nym must be 3-32 lowercase letters, numbers, or hyphens',
      );
    }
    if (header.isEmpty || utf8ByteLength(header) > 80) {
      throw const PaymentPageValidationError(
        'must be between 1 and 80 characters',
      );
    }
    if (description.isEmpty || utf8ByteLength(description) > 280) {
      throw const PaymentPageValidationError(
        'must be between 1 and 280 characters',
      );
    }
    if (!paymentPageSupportedDisplayCurrencies.contains(displayCurrency)) {
      throw PaymentPageValidationError(
        'display currency must be one of ${paymentPageSupportedDisplayCurrencies.join(', ')}',
      );
    }

    final websiteValue = website;
    if (websiteValue != null &&
        websiteValue.isNotEmpty &&
        (!websiteValue.startsWith('https://') ||
            utf8ByteLength(websiteValue) > 200)) {
      throw const PaymentPageValidationError(
        'must start with https:// and be at most 200 characters',
      );
    }

    final twitterValue = twitter;
    if (twitterValue != null &&
        twitterValue.isNotEmpty &&
        !_twitterHandleRegex.hasMatch(twitterValue)) {
      throw const PaymentPageValidationError(
        'must be 1-50 alphanumeric or underscore characters',
      );
    }

    final instagramValue = instagram;
    if (instagramValue != null &&
        instagramValue.isNotEmpty &&
        !_instagramHandleRegex.hasMatch(instagramValue)) {
      throw const PaymentPageValidationError(
        'must be 1-50 alphanumeric, dot, or underscore characters',
      );
    }
  }
}
