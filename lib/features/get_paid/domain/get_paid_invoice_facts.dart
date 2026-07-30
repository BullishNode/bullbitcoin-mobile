enum GetPaidInvoiceStatus {
  unpaid,
  inProgress,
  partiallyPaid,
  paid,
  underpaid,
  overpaid,
  expired,
  cancelled,
  unsupported,
}

enum GetPaidInvoiceSettlementState { none, pending, settled, problem }

enum GetPaidInvoiceRail { bitcoin, lightning, liquid }

enum GetPaidInvoicePaymentEventState { pending, confirming, settled, problem }

enum GetPaidInvoicePaymentProblem {
  evicted,
  reorged,
  conflicted,
  replaced,
  unknown,
}

class GetPaidInvoicePaymentEvent {
  final GetPaidInvoiceRail rail;
  final int amountSat;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final GetPaidInvoicePaymentEventState state;
  final int confirmations;
  final String? transactionId;
  final int? outputIndex;
  final bool isLate;
  final GetPaidInvoicePaymentProblem? problem;

  const GetPaidInvoicePaymentEvent({
    required this.rail,
    required this.amountSat,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.state,
    required this.confirmations,
    required this.transactionId,
    required this.outputIndex,
    required this.isLate,
    required this.problem,
  });

  bool get isProvisional =>
      state == GetPaidInvoicePaymentEventState.pending ||
      state == GetPaidInvoicePaymentEventState.confirming;
}

/// Get Paid's narrow, merchant-only view of authenticated invoice accounting. The Invoices feature's entity is mapped at the use-case boundary and never enters Get Paid presentation state.
class GetPaidInvoicePaymentSummary {
  final int observedAmountSat;
  final int creditedAmountSat;
  final int remainingAmountSat;
  final int excessAmountSat;
  final int logicalPaymentCount;

  const GetPaidInvoicePaymentSummary({
    required this.observedAmountSat,
    required this.creditedAmountSat,
    required this.remainingAmountSat,
    required this.excessAmountSat,
    required this.logicalPaymentCount,
  });
}

/// Get Paid's presentation-safe invoice facts. The Invoices feature's public entity and authenticated accounting summary are mapped into this record at the use-case boundary and never enter Get Paid presentation state.
class GetPaidInvoiceFacts {
  final GetPaidInvoiceStatus status;
  final GetPaidInvoiceSettlementState settlementState;
  final String pricingMode;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final int remainingAmountSat;
  final GetPaidInvoicePaymentSummary? paymentSummary;
  final bool paymentSummaryUnavailable;
  final int paymentToleranceSat;
  final int? creationRateMinorPerBtc;
  final DateTime rateLocksUntil;
  final DateTime expiresAt;
  final GetPaidInvoiceRail? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final List<GetPaidInvoicePaymentEvent> paymentEvents;
  final bool presentationMarksLatePayment;

  const GetPaidInvoiceFacts({
    required this.status,
    required this.settlementState,
    required this.pricingMode,
    required this.amountSat,
    required this.fiatAmountMinor,
    required this.fiatCurrency,
    required this.remainingAmountSat,
    required this.paymentSummary,
    required this.paymentSummaryUnavailable,
    required this.paymentToleranceSat,
    required this.creationRateMinorPerBtc,
    required this.rateLocksUntil,
    required this.expiresAt,
    required this.paidVia,
    required this.paidAt,
    required this.paidAmountSat,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.paymentEvents,
    required this.presentationMarksLatePayment,
  });

  bool get isFiatFixed => pricingMode == 'fiat_fixed';
  bool get hasSatTarget => amountSat > 0;
  bool get hasFiatFace =>
      fiatAmountMinor != null && (fiatCurrency?.trim().isNotEmpty ?? false);

  bool get _statusIsTerminal => switch (status) {
    GetPaidInvoiceStatus.paid ||
    GetPaidInvoiceStatus.underpaid ||
    GetPaidInvoiceStatus.overpaid ||
    GetPaidInvoiceStatus.expired ||
    GetPaidInvoiceStatus.cancelled => true,
    _ => false,
  };

  bool get hasPublicPaymentEvidence =>
      paymentEvents.isNotEmpty ||
      paidAmountSat != null ||
      paidAt != null ||
      paidVia != null ||
      status == GetPaidInvoiceStatus.inProgress ||
      status == GetPaidInvoiceStatus.partiallyPaid ||
      status == GetPaidInvoiceStatus.paid ||
      status == GetPaidInvoiceStatus.underpaid ||
      status == GetPaidInvoiceStatus.overpaid;

  bool get shouldShowPaymentSummaryUnavailable => paymentSummaryUnavailable;

  bool get isAwaitingConfirmation =>
      !_statusIsTerminal &&
      (paymentEvents.any((event) => event.isProvisional) ||
          paidAmountSat != null);

  bool get hasLatePayment =>
      presentationMarksLatePayment ||
      paymentEvents.any((event) => event.isLate) ||
      (paidAt != null &&
          (!expiresAt.isAfter(paidAt!) ||
              status == GetPaidInvoiceStatus.cancelled));

  int? get overpaidAmountSat {
    final paid = paidAmountSat;
    if (!hasSatTarget || paid == null || paid <= amountSat) return null;
    return paid - amountSat;
  }
}
