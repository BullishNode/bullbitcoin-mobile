import 'package:bb_mobile/core/errors/bull_exception.dart';

enum BtcpayPairingExceptionType {
  invalidRequest,
  localSetup,
  rejected,
  uncertain,
  generic,
}

class BtcpayPairingException extends BullException {
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

  factory BtcpayPairingException.localSetup([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.localSetup,
      _safeMessage(message) ??
          'Dedicated BTCPay wallets were kept, but local setup did not finish',
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

class SamRockSetupPayloadException extends BullException {
  SamRockSetupPayloadException(super.message);
}

String? _safeMessage(String? message) {
  final trimmed = message?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
