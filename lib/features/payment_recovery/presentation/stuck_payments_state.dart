import 'package:bb_mobile/features/payment_recovery/domain/entities/stuck_payment.dart';

/// Read-only view state for the stuck-payments list. [payments] is the live
/// store view (watch stream); [recoveryActionEnabled] and [hasMore] come from
/// the last scan and gate the recover UI vs "contact support".
class StuckPaymentsState {
  final bool isLoading;
  final List<StuckPayment> payments;
  final bool recoveryActionEnabled;
  final bool hasMore;

  const StuckPaymentsState({
    this.isLoading = false,
    this.payments = const [],
    this.recoveryActionEnabled = false,
    this.hasMore = false,
  });

  /// Only rows still needing attention are shown at the top; recovered/dismissed
  /// history is filtered out of the primary list.
  List<StuckPayment> get needsAttention =>
      payments.where((p) => p.needsAttention).toList();

  StuckPaymentsState copyWith({
    bool? isLoading,
    List<StuckPayment>? payments,
    bool? recoveryActionEnabled,
    bool? hasMore,
  }) {
    return StuckPaymentsState(
      isLoading: isLoading ?? this.isLoading,
      payments: payments ?? this.payments,
      recoveryActionEnabled: recoveryActionEnabled ?? this.recoveryActionEnabled,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}
