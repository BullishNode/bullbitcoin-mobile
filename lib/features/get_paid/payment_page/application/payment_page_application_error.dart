sealed class PaymentPageApplicationError implements Exception {
  final String message;

  const PaymentPageApplicationError(this.message);

  factory PaymentPageApplicationError.fromCode({
    required String code,
    required String reason,
  }) {
    return switch (code) {
      'DonationPageNotFound' => PaymentPageNotFoundError(reason),
      'AuthError' => PaymentPageAuthorizationError(reason),
      'DonationPageInvalid' => PaymentPageValidationError(reason),
      'NetworkError' => PaymentPageNetworkError(reason),
      _ => PaymentPageUnexpectedError(reason),
    };
  }

  @override
  String toString() => message;
}

class PaymentPageNotFoundError extends PaymentPageApplicationError {
  const PaymentPageNotFoundError(super.message);
}

class PaymentPageAuthorizationError extends PaymentPageApplicationError {
  const PaymentPageAuthorizationError(super.message);
}

class PaymentPageValidationError extends PaymentPageApplicationError {
  const PaymentPageValidationError(super.message);
}

class PaymentPageNetworkError extends PaymentPageApplicationError {
  const PaymentPageNetworkError(super.message);
}

class PaymentPageIdentityUnavailableError extends PaymentPageApplicationError {
  const PaymentPageIdentityUnavailableError(super.message);
}

class PaymentPageUnexpectedError extends PaymentPageApplicationError {
  const PaymentPageUnexpectedError(super.message);
}
