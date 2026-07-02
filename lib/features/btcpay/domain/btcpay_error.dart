import 'package:bb_mobile/core/errors/bull_exception.dart';

enum BtcpayPairingExceptionType { invalidRequest, rejected, uncertain, generic }

sealed class BtcpayError extends BullException {
  BtcpayError(super.message);
}

final class BtcpayPairingException extends BtcpayError {
  final BtcpayPairingExceptionType type;

  BtcpayPairingException._(this.type, super.message);

  factory BtcpayPairingException.invalidRequest([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.invalidRequest,
      _safeMessage(message) ?? 'Invalid BTCPay SamRock pairing request',
    );
  }

  factory BtcpayPairingException.rejected([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.rejected,
      _safeMessage(message) ?? 'BTCPay Server rejected the SamRock setup',
    );
  }

  factory BtcpayPairingException.uncertain([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.uncertain,
      _safeMessage(message) ??
          'BTCPay setup was submitted, but completion could not be confirmed',
    );
  }

  factory BtcpayPairingException.generic([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.generic,
      _safeMessage(message) ?? 'Could not pair BTCPay Server',
    );
  }
}

final class SamRockSetupPayloadException extends BtcpayError {
  SamRockSetupPayloadException(super.message);
}

String? _safeMessage(String? message) {
  final trimmed = message?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
