enum BtcpayPairingStatus { idle, submitting, success, failure }

enum BtcpayPairingFailure { invalidRequest, rejected, generic }

class BtcpayPairingState {
  final BtcpayPairingStatus status;
  final BtcpayPairingFailure? failure;
  final String? failureMessage;

  const BtcpayPairingState({
    this.status = BtcpayPairingStatus.idle,
    this.failure,
    this.failureMessage,
  });

  bool get isSubmitting => status == BtcpayPairingStatus.submitting;
  bool get isSuccess => status == BtcpayPairingStatus.success;
  bool get isFailure => status == BtcpayPairingStatus.failure;
}
