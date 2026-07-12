import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';

enum PaymentRecoveryErrorKind {
  /// No default Bitcoin wallet / seed to derive the signing identity or a
  /// refund address (locked, superwallet mode).
  noDefaultBitcoinWallet,

  /// Local signing failed (key derivation).
  signingFailed,

  /// The recover ACTION is not available: server flag off or route absent
  /// (404). Detection still works; the stuck row stays visible read-only.
  recoveryUnavailable,

  /// A recover broadcast is already in flight server-side — poll to completion.
  recoveryInProgress,

  /// The server has no recoverable swap for this invoice (recovered elsewhere,
  /// or stale detection).
  recoveryNotAvailable,

  /// A different refund address was already committed for this swap (multi-
  /// device race / skipped-scan). Never overwrite the local address; surface.
  addressMismatch,

  /// The refund address was rejected (should be impossible for own-wallet
  /// mainnet derivation).
  addressInvalid,

  /// Ownership/nym drift — not recoverable from this wallet.
  notFound,

  network,
  timeout,
  invalidServerResponse,
  server,
  unexpected,
}

/// Typed recovery errors, mirroring `InvoicesException`. The server `reason`
/// string is diagnostic-only and never surfaced (charter C3); only the stable
/// `code` drives the mapping.
sealed class PaymentRecoveryException implements Exception {
  final PaymentRecoveryErrorKind kind;
  final String code;
  final bool retryable;

  const PaymentRecoveryException._({
    required this.kind,
    required this.code,
    required this.retryable,
  });

  const factory PaymentRecoveryException.noDefaultBitcoinWallet() =
      PaymentRecoveryNoDefaultBitcoinWalletException;
  const factory PaymentRecoveryException.signingFailed() =
      PaymentRecoverySigningFailedException;
  const factory PaymentRecoveryException.recoveryUnavailable() =
      PaymentRecoveryUnavailableException;
  const factory PaymentRecoveryException.recoveryInProgress() =
      PaymentRecoveryInProgressException;
  const factory PaymentRecoveryException.recoveryNotAvailable() =
      PaymentRecoveryNotAvailableException;
  const factory PaymentRecoveryException.addressMismatch() =
      PaymentRecoveryAddressMismatchException;
  const factory PaymentRecoveryException.addressInvalid() =
      PaymentRecoveryAddressInvalidException;
  const factory PaymentRecoveryException.notFound() =
      PaymentRecoveryNotFoundException;
  const factory PaymentRecoveryException.network() =
      PaymentRecoveryNetworkException;
  const factory PaymentRecoveryException.timeout() =
      PaymentRecoveryTimeoutException;
  const factory PaymentRecoveryException.invalidServerResponse() =
      PaymentRecoveryInvalidServerResponseException;
  const factory PaymentRecoveryException.server({required bool retryable}) =
      PaymentRecoveryServerException;
  const factory PaymentRecoveryException.unexpected() =
      PaymentRecoveryUnexpectedException;
  const factory PaymentRecoveryException.storage({required Object cause}) =
      PaymentRecoveryStorageException;

  /// Map a shared-client [BullnymException] onto the recovery family. A
  /// route-absent server (`unexpectedHttpStatus`, e.g. 404) maps to
  /// `recoveryUnavailable` so the feature FAILS CLOSED (funds stay visible),
  /// never pretending recovery happened.
  factory PaymentRecoveryException.fromBullnym(BullnymException error) {
    return switch (error.kind) {
      BullnymErrorKind.network => const PaymentRecoveryException.network(),
      BullnymErrorKind.timeout => const PaymentRecoveryException.timeout(),
      BullnymErrorKind.serverRejectedRequest => switch (error.code) {
        'RecoveryInProgress' =>
          const PaymentRecoveryException.recoveryInProgress(),
        'RecoveryNotAvailable' =>
          const PaymentRecoveryException.recoveryNotAvailable(),
        'RecoveryAddressInvalid' =>
          const PaymentRecoveryException.addressInvalid(),
        'InvoiceNotFound' => const PaymentRecoveryException.notFound(),
        _ => PaymentRecoveryException.server(retryable: error.retryable),
      },
      BullnymErrorKind.unexpectedHttpStatus =>
        const PaymentRecoveryException.recoveryUnavailable(),
      BullnymErrorKind.emptyResponse ||
      BullnymErrorKind.invalidServerResponse =>
        const PaymentRecoveryException.invalidServerResponse(),
      BullnymErrorKind.signingFailed =>
        const PaymentRecoveryException.signingFailed(),
      BullnymErrorKind.invalidInput =>
        const PaymentRecoveryException.unexpected(),
    };
  }

  @override
  String toString() => 'PaymentRecoveryException($code)';
}

final class PaymentRecoveryNoDefaultBitcoinWalletException
    extends PaymentRecoveryException {
  const PaymentRecoveryNoDefaultBitcoinWalletException()
    : super._(
        kind: PaymentRecoveryErrorKind.noDefaultBitcoinWallet,
        code: 'NoDefaultBitcoinWallet',
        retryable: false,
      );
}

final class PaymentRecoverySigningFailedException
    extends PaymentRecoveryException {
  const PaymentRecoverySigningFailedException()
    : super._(
        kind: PaymentRecoveryErrorKind.signingFailed,
        code: 'SigningFailed',
        retryable: false,
      );
}

final class PaymentRecoveryUnavailableException
    extends PaymentRecoveryException {
  const PaymentRecoveryUnavailableException()
    : super._(
        kind: PaymentRecoveryErrorKind.recoveryUnavailable,
        code: 'RecoveryUnavailable',
        retryable: true,
      );
}

final class PaymentRecoveryInProgressException
    extends PaymentRecoveryException {
  const PaymentRecoveryInProgressException()
    : super._(
        kind: PaymentRecoveryErrorKind.recoveryInProgress,
        code: 'RecoveryInProgress',
        retryable: true,
      );
}

final class PaymentRecoveryNotAvailableException
    extends PaymentRecoveryException {
  const PaymentRecoveryNotAvailableException()
    : super._(
        kind: PaymentRecoveryErrorKind.recoveryNotAvailable,
        code: 'RecoveryNotAvailable',
        retryable: false,
      );
}

final class PaymentRecoveryAddressMismatchException
    extends PaymentRecoveryException {
  const PaymentRecoveryAddressMismatchException()
    : super._(
        kind: PaymentRecoveryErrorKind.addressMismatch,
        code: 'RecoveryAddressMismatch',
        retryable: false,
      );
}

final class PaymentRecoveryAddressInvalidException
    extends PaymentRecoveryException {
  const PaymentRecoveryAddressInvalidException()
    : super._(
        kind: PaymentRecoveryErrorKind.addressInvalid,
        code: 'RecoveryAddressInvalid',
        retryable: false,
      );
}

final class PaymentRecoveryNotFoundException extends PaymentRecoveryException {
  const PaymentRecoveryNotFoundException()
    : super._(
        kind: PaymentRecoveryErrorKind.notFound,
        code: 'InvoiceNotFound',
        retryable: false,
      );
}

final class PaymentRecoveryNetworkException extends PaymentRecoveryException {
  const PaymentRecoveryNetworkException()
    : super._(
        kind: PaymentRecoveryErrorKind.network,
        code: 'NetworkError',
        retryable: true,
      );
}

final class PaymentRecoveryTimeoutException extends PaymentRecoveryException {
  const PaymentRecoveryTimeoutException()
    : super._(
        kind: PaymentRecoveryErrorKind.timeout,
        code: 'Timeout',
        retryable: true,
      );
}

final class PaymentRecoveryInvalidServerResponseException
    extends PaymentRecoveryException {
  const PaymentRecoveryInvalidServerResponseException()
    : super._(
        kind: PaymentRecoveryErrorKind.invalidServerResponse,
        code: 'InvalidServerResponse',
        retryable: true,
      );
}

final class PaymentRecoveryServerException extends PaymentRecoveryException {
  const PaymentRecoveryServerException({required super.retryable})
    : super._(kind: PaymentRecoveryErrorKind.server, code: 'ServerError');
}

final class PaymentRecoveryUnexpectedException
    extends PaymentRecoveryException {
  const PaymentRecoveryUnexpectedException()
    : super._(
        kind: PaymentRecoveryErrorKind.unexpected,
        code: 'Unexpected',
        retryable: false,
      );
}

final class PaymentRecoveryStorageException extends PaymentRecoveryException {
  final Object cause;
  const PaymentRecoveryStorageException({required this.cause})
    : super._(
        kind: PaymentRecoveryErrorKind.unexpected,
        code: 'StorageError',
        retryable: false,
      );
}
