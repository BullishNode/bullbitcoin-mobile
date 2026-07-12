import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';

/// Detail-screen state for a single stuck payment. [payment] tracks the live
/// store row; [recoveryActionEnabled]/[hasMore] come from the last scan and
/// gate the recover button vs the "contact support" surface; [isBusy] drives
/// the button spinner while a recover attempt (and its poll) is in flight.
class StuckPaymentDetailState {
  final StuckPayment? payment;
  final bool recoveryActionEnabled;
  final bool hasMore;
  final bool isBusy;

  const StuckPaymentDetailState({
    this.payment,
    this.recoveryActionEnabled = false,
    this.hasMore = false,
    this.isBusy = false,
  });

  StuckPaymentDetailState copyWith({
    StuckPayment? payment,
    bool clearPayment = false,
    bool? recoveryActionEnabled,
    bool? hasMore,
    bool? isBusy,
  }) {
    return StuckPaymentDetailState(
      payment: clearPayment ? null : payment ?? this.payment,
      recoveryActionEnabled:
          recoveryActionEnabled ?? this.recoveryActionEnabled,
      hasMore: hasMore ?? this.hasMore,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}
