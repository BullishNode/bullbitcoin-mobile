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

class GetPaidInvoicePayerAmount {
  final GetPaidInvoiceRail rail;
  final int merchantTargetAmountSat;
  final int payerAmountSat;

  const GetPaidInvoicePayerAmount({
    required this.rail,
    required this.merchantTargetAmountSat,
    required this.payerAmountSat,
  });

  int get checkoutCostSat => payerAmountSat - merchantTargetAmountSat;
}

class GetPaidInvoiceRailAvailability {
  final bool lightning;
  final bool liquid;
  final bool bitcoin;

  const GetPaidInvoiceRailAvailability({
    required this.lightning,
    required this.liquid,
    required this.bitcoin,
  });
}

/// Get Paid's narrow, merchant-only view of authenticated invoice accounting.
/// The Invoices feature's entity is mapped at the use-case boundary and never
/// enters Get Paid presentation state.
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

  bool get hasPaymentEvidence =>
      observedAmountSat > 0 || logicalPaymentCount > 0;
}

/// Get Paid's presentation-safe invoice facts. The Invoices feature's public
/// entity and authenticated accounting summary are mapped into this record at
/// the use-case boundary and never enter Get Paid presentation state.
class GetPaidInvoiceFacts {
  final GetPaidInvoiceStatus status;
  final GetPaidInvoiceSettlementState settlementState;
  final String pricingMode;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final int remainingAmountSat;
  final bool? acceptingPayments;
  final bool topUpAllowed;
  final bool authenticatedPaymentEvidence;
  final GetPaidInvoicePaymentSummary? paymentSummary;
  final bool paymentSummaryUnavailable;
  final int paymentToleranceSat;
  final int? rateMinorPerBtc;
  final int? creationRateMinorPerBtc;
  final DateTime rateLocksUntil;
  final DateTime expiresAt;
  final GetPaidInvoiceRail? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final String? lightningPr;
  final String? liquidAddress;
  final String? bitcoinAddress;
  final String? bitcoinChainAddress;
  final String? bitcoinChainBip21;
  final List<GetPaidInvoicePayerAmount> payerAmounts;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final GetPaidInvoiceRailAvailability? quoteRailAvailability;
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
    required this.acceptingPayments,
    required this.topUpAllowed,
    required this.authenticatedPaymentEvidence,
    required this.paymentSummary,
    required this.paymentSummaryUnavailable,
    required this.paymentToleranceSat,
    required this.rateMinorPerBtc,
    required this.creationRateMinorPerBtc,
    required this.rateLocksUntil,
    required this.expiresAt,
    required this.paidVia,
    required this.paidAt,
    required this.paidAmountSat,
    required this.lightningPr,
    required this.liquidAddress,
    required this.bitcoinAddress,
    required this.bitcoinChainAddress,
    required this.bitcoinChainBip21,
    required this.payerAmounts,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    required this.quoteRailAvailability,
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

  bool get hasPaymentEvidence =>
      authenticatedPaymentEvidence ||
      (paymentSummary?.hasPaymentEvidence ?? false) ||
      hasPublicPaymentEvidence;

  bool get shouldShowPaymentSummaryUnavailable =>
      hasPaymentEvidence && paymentSummaryUnavailable;

  /// Whether public invoice state permits the initial payment request now.
  /// Authenticated evidence always closes admission. [topUpAllowed] is not an
  /// initial-payment authorization and deliberately does not participate.
  bool acceptsInitialPayment(DateTime now) =>
      status == GetPaidInvoiceStatus.unpaid &&
      !hasPaymentEvidence &&
      (acceptingPayments ?? true) &&
      expiresAt.isAfter(now);

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
