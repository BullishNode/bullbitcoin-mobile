sealed class InvoicesApplicationError implements Exception {
  final String message;

  const InvoicesApplicationError(this.message);

  factory InvoicesApplicationError.fromCode({
    required String code,
    required String reason,
  }) {
    return switch (code) {
      'InvoiceNotFound' => InvoicesNotFoundError(reason),
      'AuthError' => InvoicesAuthorizationError(reason),
      'InvalidAmount' => InvoicesValidationError(reason),
      'ValidationError' => InvoicesValidationError(reason),
      'BitcoinAddressAlreadyUsed' => InvoicesBitcoinAddressAlreadyUsedError(
        reason,
      ),
      'LiquidAddressAlreadyUsed' => InvoicesLiquidAddressAlreadyUsedError(
        reason,
      ),
      'RateLimited' => InvoicesRateLimitedError(reason),
      'NetworkError' => InvoicesNetworkError(reason),
      _ => InvoicesUnexpectedError(reason),
    };
  }

  @override
  String toString() => message;
}

class InvoicesNotFoundError extends InvoicesApplicationError {
  const InvoicesNotFoundError(super.message);
}

class InvoicesAuthorizationError extends InvoicesApplicationError {
  const InvoicesAuthorizationError(super.message);
}

class InvoicesValidationError extends InvoicesApplicationError {
  const InvoicesValidationError(super.message);
}

class InvoicesRateLimitedError extends InvoicesApplicationError {
  const InvoicesRateLimitedError(super.message);
}

class InvoicesNetworkError extends InvoicesApplicationError {
  const InvoicesNetworkError(super.message);
}

class InvoicesNoDefaultBitcoinWalletError extends InvoicesApplicationError {
  const InvoicesNoDefaultBitcoinWalletError(super.message);
}

class InvoicesNoDefaultLiquidWalletError extends InvoicesApplicationError {
  const InvoicesNoDefaultLiquidWalletError(super.message);
}

class InvoicesBitcoinAddressAlreadyUsedError extends InvoicesApplicationError {
  const InvoicesBitcoinAddressAlreadyUsedError(super.message);
}

class InvoicesLiquidAddressAlreadyUsedError extends InvoicesApplicationError {
  const InvoicesLiquidAddressAlreadyUsedError(super.message);
}

class InvoicesIdentityUnavailableError extends InvoicesApplicationError {
  const InvoicesIdentityUnavailableError(super.message);
}

class InvoicesUnexpectedError extends InvoicesApplicationError {
  const InvoicesUnexpectedError(super.message);
}
