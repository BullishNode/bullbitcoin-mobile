import 'package:bb_mobile/core/errors/bull_exception.dart';

enum BtcpayPairingExceptionType { invalidRequest, rejected, generic }

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

  factory BtcpayPairingException.generic([String? message]) {
    return BtcpayPairingException._(
      BtcpayPairingExceptionType.generic,
      _safeMessage(message) ?? 'Could not pair BTCPay Server',
    );
  }
}

String? _safeMessage(String? message) {
  final trimmed = message?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed.length <= 160 ? trimmed : '${trimmed.substring(0, 160)}...';
}
