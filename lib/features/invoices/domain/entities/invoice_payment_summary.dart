/// Bullnym's authenticated merchant-only fiat accounting for one invoice.
class InvoiceFiatPaymentSummary {
  final String currency;
  final int targetAmountMinor;
  final int creditedAmountMinor;
  final int remainingAmountMinor;

  InvoiceFiatPaymentSummary({
    required this.currency,
    required this.targetAmountMinor,
    required this.creditedAmountMinor,
    required this.remainingAmountMinor,
  }) {
    if (currency.trim().isEmpty ||
        targetAmountMinor < 0 ||
        creditedAmountMinor < 0 ||
        remainingAmountMinor < 0) {
      throw ArgumentError('Invalid invoice fiat payment summary');
    }
  }
}

/// Bullnym's authenticated merchant-only payment projection. These are server
/// facts, not values reconstructed from settlement legs or public invoice data.
class InvoicePaymentSummary {
  final int observedAmountSat;
  final int creditedAmountSat;
  final int remainingAmountSat;
  final int excessAmountSat;
  final int logicalPaymentCount;
  final bool multiplePayments;
  final int latePaymentCount;
  final bool hasLatePayment;
  final DateTime? firstPaymentAt;
  final DateTime? lastPaymentAt;
  final bool acceptingPayments;
  final bool topUpAllowed;
  final bool requiresMerchantAction;
  final List<String> attentionReasons;
  final InvoiceFiatPaymentSummary? fiat;

  InvoicePaymentSummary({
    required this.observedAmountSat,
    required this.creditedAmountSat,
    required this.remainingAmountSat,
    required this.excessAmountSat,
    required this.logicalPaymentCount,
    required this.multiplePayments,
    required this.latePaymentCount,
    required this.hasLatePayment,
    required this.firstPaymentAt,
    required this.lastPaymentAt,
    required this.acceptingPayments,
    required this.topUpAllowed,
    required this.requiresMerchantAction,
    required List<String> attentionReasons,
    required this.fiat,
  }) : attentionReasons = List.unmodifiable(attentionReasons) {
    if (observedAmountSat < 0 ||
        creditedAmountSat < 0 ||
        remainingAmountSat < 0 ||
        excessAmountSat < 0 ||
        logicalPaymentCount < 0 ||
        latePaymentCount < 0 ||
        multiplePayments != (logicalPaymentCount > 1) ||
        hasLatePayment != (latePaymentCount > 0) ||
        (firstPaymentAt != null &&
            lastPaymentAt != null &&
            firstPaymentAt!.isAfter(lastPaymentAt!)) ||
        attentionReasons.any((reason) => reason.trim().isEmpty)) {
      throw ArgumentError('Invalid invoice payment summary');
    }
  }

  bool get hasPaymentEvidence =>
      observedAmountSat > 0 || logicalPaymentCount > 0;
}
