import 'package:bb_mobile/features/get_paid/btcpay/domain/btcpay_connection.dart';

enum BtcpayPairingStatus { idle, submitting, success, failure }

enum BtcpayPairingFailure { invalidRequest, rejected, generic }

class BtcpayPairingState {
  final BtcpayPairingStatus status;
  final BtcpayPairingFailure? failure;
  final String? failureMessage;
  final BtcpayConnection? connection;
  final bool showPairingForm;

  const BtcpayPairingState({
    this.status = BtcpayPairingStatus.idle,
    this.failure,
    this.failureMessage,
    this.connection,
    this.showPairingForm = false,
  });

  bool get isSubmitting => status == BtcpayPairingStatus.submitting;
  bool get isSuccess => status == BtcpayPairingStatus.success;
  bool get isFailure => status == BtcpayPairingStatus.failure;
  bool get shouldShowConnection =>
      connection != null && !showPairingForm && !isSuccess;

  BtcpayPairingState copyWith({
    BtcpayPairingStatus? status,
    BtcpayPairingFailure? failure,
    String? failureMessage,
    BtcpayConnection? connection,
    bool clearFailure = false,
    bool clearFailureMessage = false,
    bool clearConnection = false,
    bool? showPairingForm,
  }) {
    return BtcpayPairingState(
      status: status ?? this.status,
      failure: clearFailure ? null : failure ?? this.failure,
      failureMessage: clearFailureMessage
          ? null
          : failureMessage ?? this.failureMessage,
      connection: clearConnection ? null : connection ?? this.connection,
      showPairingForm: showPairingForm ?? this.showPairingForm,
    );
  }
}
