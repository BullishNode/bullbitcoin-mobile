import 'package:bb_mobile/features/invoices/domain/entities/invoice_payment_event.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_payer_amount.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_quote.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/payment_method.dart';

/// The public status/detail view of an invoice (server `InvoiceStatusResponse`,
/// unsigned GET by id). Kept DISTINCT from [Invoice] (§3.11): the detail screen
/// merges this with the list [Invoice] explicitly, it never conflates them.
class InvoiceStatusSnapshot {
  final InvoiceStatus status;
  final InvoiceSettlementState settlementState;
  final String pricingMode;
  final String settlementStatus;
  final int amountSat;
  final int? fiatAmountMinor;
  final String? fiatCurrency;
  final int remainingAmountSat;
  final int paymentToleranceSat;
  final int? rateMinorPerBtc;
  final DateTime rateLocksUntil;
  final DateTime expiresAt;
  final PaymentMethod? paidVia;
  final DateTime? paidAt;
  final int? paidAmountSat;
  final String? lightningPr;
  final InvoicePayerAmount? lightningPayerAmount;
  final String? liquidAddress;
  final InvoicePayerAmount? liquidPayerAmount;
  final String? bitcoinAddress;
  final String? bitcoinChainAddress;
  final String? bitcoinChainBip21;
  final InvoicePayerAmount? bitcoinChainPayerAmount;
  final bool acceptBtc;
  final bool acceptLn;
  final bool acceptLiquid;
  final InvoiceQuoteRailAvailability? quoteRailAvailability;
  final List<InvoicePaymentEvent> paymentEvents;
  final bool presentationMarksLatePayment;

  const InvoiceStatusSnapshot({
    required this.status,
    this.settlementState = InvoiceSettlementState.none,
    required this.pricingMode,
    required this.settlementStatus,
    required this.amountSat,
    this.fiatAmountMinor,
    this.fiatCurrency,
    required this.remainingAmountSat,
    required this.paymentToleranceSat,
    this.rateMinorPerBtc,
    required this.rateLocksUntil,
    required this.expiresAt,
    this.paidVia,
    this.paidAt,
    this.paidAmountSat,
    this.lightningPr,
    this.lightningPayerAmount,
    this.liquidAddress,
    this.liquidPayerAmount,
    this.bitcoinAddress,
    this.bitcoinChainAddress,
    this.bitcoinChainBip21,
    this.bitcoinChainPayerAmount,
    required this.acceptBtc,
    required this.acceptLn,
    required this.acceptLiquid,
    this.quoteRailAvailability,
    this.paymentEvents = const [],
    this.presentationMarksLatePayment = false,
  });

  /// True only when lifecycle and settlement supervision are both complete.
  bool get isTerminal => isMonitoringComplete;

  bool get isFiatFixed => pricingMode == 'fiat_fixed';

  /// The invoice's durable merchant face value, distinct from payer gross-up.
  int get merchantFaceAmountSat => amountSat;

  /// A positive locked satoshi target exists on the invoice row. Fiat-priced
  /// invoices (`pricing_mode` fiat_fixed) carry no sat target, so [amountSat]
  /// is 0 and settlement facts must never be derived from it.
  bool get hasSatTarget => amountSat > 0;

  /// A fiat face value is present to headline (fiat-priced invoices carry the
  /// face amount in fiat, not sats).
  bool get hasFiatFace =>
      fiatAmountMinor != null && (fiatCurrency?.trim().isNotEmpty ?? false);

  /// Overpayment is only derivable against a positive sat target. For a
  /// fiat-priced invoice (`amountSat == 0`) any payment would otherwise read as
  /// a full-amount overpayment, so this returns null and the lifecycle status
  /// enum alone ([InvoiceStatus.overpaid]) conveys overpayment.
  int? get overpaidAmountSat {
    final paid = paidAmountSat;
    if (!hasSatTarget || paid == null || paid <= amountSat) return null;
    return paid - amountSat;
  }

  /// The invoice is still genuinely waiting for a payer: no payment evidence
  /// yet and the lifecycle is not terminal. A payer quote (and any
  /// quote-unavailability messaging) is only meaningful in this window; payer
  /// quotes carry a 5-minute TTL, so a later re-read shows no rails even though
  /// nothing is wrong.
  bool get isAwaitingPayer => !hasPaymentEvidence && !status.isTerminal;

  bool get hasProvisionalPaymentEvidence =>
      paymentEvents.any((event) => event.isProvisional);

  /// On-chain payment has been observed but the invoice has not yet flipped to
  /// a terminal state (the server marks paid at the first confirmation). During
  /// 0-conf this surfaces an honest "waiting for confirmation" state instead of
  /// a bare in-progress.
  bool get isAwaitingConfirmation =>
      !status.isTerminal &&
      (hasProvisionalPaymentEvidence || paidAmountSat != null);

  /// Exact currently payable amounts in the approved rail order.
  List<InvoicePayerAmount> get payerAmounts => [
    ?lightningPayerAmount,
    ?liquidPayerAmount,
    ?bitcoinChainPayerAmount,
  ];

  bool get hasPaymentEvidence =>
      paymentEvents.isNotEmpty ||
      paidAmountSat != null ||
      paidAt != null ||
      paidVia != null ||
      status == InvoiceStatus.inProgress ||
      status == InvoiceStatus.partiallyPaid ||
      status == InvoiceStatus.paid ||
      status == InvoiceStatus.underpaid ||
      status == InvoiceStatus.overpaid;

  bool get hasLatePayment =>
      presentationMarksLatePayment ||
      paymentEvents.any((event) => event.isLate) ||
      (paidAt != null &&
          (!expiresAt.isAfter(paidAt!) || status == InvoiceStatus.cancelled));

  bool get isSettlementPending =>
      settlementState == InvoiceSettlementState.pending;

  bool get hasSettlementProblem =>
      settlementState == InvoiceSettlementState.problem;

  /// A lifecycle-terminal invoice still needs polling until provisional or
  /// problematic settlement evidence reaches a resolved state.
  bool get isMonitoringComplete =>
      status.isTerminal &&
      settlementState != InvoiceSettlementState.pending &&
      settlementState != InvoiceSettlementState.problem;

  bool get isCancellable => status == InvoiceStatus.unpaid;

  Duration timeUntilExpiry(DateTime now) {
    final remaining = expiresAt.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
