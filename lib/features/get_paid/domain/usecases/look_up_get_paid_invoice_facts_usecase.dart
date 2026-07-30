import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';
import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';
import 'package:meta/meta.dart';

/// Get Paid's narrow wrapper over the invoices boundary for the transaction detail card: read the entry's own invoice state.
///
/// The invoices failure family stays behind the boundary — a rejected or thrown read becomes a Get Paid-owned [GetPaidFailure] that the card states, rather than rendering as though the entry had no invoice. An entry carrying an invoice id must never read as an invoice-less payment.
class LookUpGetPaidInvoiceFactsUsecase {
  final InvoicesFacade _invoices;

  const LookUpGetPaidInvoiceFactsUsecase({required this._invoices});

  @useResult
  Future<Result<GetPaidInvoiceFacts, GetPaidFailure>> execute({
    required String invoiceId,
  }) async {
    final id = InvoiceId(invoiceId);
    late final InvoiceStatusSnapshot publicInvoice;
    try {
      final result = await _invoices.status(id);
      switch (result) {
        case Ok(:final value):
          publicInvoice = value;
        case Err(:final failure):
          log.warning(
            'Get Paid invoice facts lookup was rejected',
            error: failure.runtimeType,
          );
          return Err(
            GetPaidFailure.unavailable(
              logMessage: failure.runtimeType.toString(),
            ),
          );
      }
    } on Exception catch (error, trace) {
      // An operational exception makes the invoice state unreadable. Never rethrow it — an unreadable invoice must not take the card down with it. Programming errors remain visible to tests and crash reporting.
      log.warning(
        'Get Paid invoice facts lookup failed',
        error: error,
        trace: trace,
      );
      return Err(
        GetPaidFailure.unavailable(logMessage: error.runtimeType.toString()),
      );
    }

    final merchant = await _merchantSummary(id);
    return Ok(
      _map(
        publicInvoice,
        paymentSummary: merchant.summary,
        paymentSummaryUnavailable: merchant.unavailable,
      ),
    );
  }

  Future<({GetPaidInvoicePaymentSummary? summary, bool unavailable})>
  _merchantSummary(InvoiceId invoiceId) async {
    try {
      final result = await _invoices.merchantInvoice(invoiceId);
      switch (result) {
        case Ok(:final value):
          final summary = value?.paymentSummary;
          return (
            summary: summary == null ? null : _paymentSummary(summary),
            unavailable: summary == null,
          );
        case Err(:final failure):
          log.warning(
            'Get Paid authenticated invoice accounting was rejected',
            error: failure.runtimeType,
          );
          return (summary: null, unavailable: true);
      }
    } on Exception catch (error, trace) {
      // The public invoice remains useful when the authenticated accounting read is unavailable. State that gap explicitly without erasing the public receipt detail.
      log.warning(
        'Get Paid authenticated invoice accounting lookup failed',
        error: error,
        trace: trace,
      );
      return (summary: null, unavailable: true);
    }
  }

  GetPaidInvoiceFacts _map(
    InvoiceStatusSnapshot invoice, {
    required GetPaidInvoicePaymentSummary? paymentSummary,
    required bool paymentSummaryUnavailable,
  }) {
    return GetPaidInvoiceFacts(
      status: _status(invoice.status),
      settlementState: _settlementState(invoice.settlementState),
      pricingMode: invoice.pricingMode,
      amountSat: invoice.amountSat,
      fiatAmountMinor: invoice.fiatAmountMinor,
      fiatCurrency: invoice.fiatCurrency,
      remainingAmountSat: invoice.remainingAmountSat,
      paymentSummary: paymentSummary,
      paymentSummaryUnavailable: paymentSummaryUnavailable,
      paymentToleranceSat: invoice.paymentToleranceSat,
      creationRateMinorPerBtc: invoice.creationRateMinorPerBtc,
      rateLocksUntil: invoice.rateLocksUntil,
      expiresAt: invoice.expiresAt,
      paidVia: invoice.paidVia == null ? null : _rail(invoice.paidVia!),
      paidAt: invoice.paidAt,
      paidAmountSat: invoice.paidAmountSat,
      acceptBtc: invoice.acceptBtc,
      acceptLn: invoice.acceptLn,
      acceptLiquid: invoice.acceptLiquid,
      paymentEvents: [
        for (final event in invoice.paymentEvents)
          GetPaidInvoicePaymentEvent(
            rail: _rail(event.rail),
            amountSat: event.amountSat,
            firstSeenAt: event.firstSeenAt,
            lastSeenAt: event.lastSeenAt,
            state: _eventState(event.state),
            confirmations: event.confirmations,
            transactionId: event.transactionId,
            outputIndex: event.outputIndex,
            isLate: event.isLate,
            problem: event.problem == null
                ? null
                : _paymentProblem(event.problem!),
          ),
      ],
      presentationMarksLatePayment: invoice.presentationMarksLatePayment,
    );
  }

  GetPaidInvoicePaymentSummary _paymentSummary(InvoicePaymentSummary summary) =>
      GetPaidInvoicePaymentSummary(
        observedAmountSat: summary.observedAmountSat,
        creditedAmountSat: summary.creditedAmountSat,
        remainingAmountSat: summary.remainingAmountSat,
        excessAmountSat: summary.excessAmountSat,
        logicalPaymentCount: summary.logicalPaymentCount,
      );

  GetPaidInvoiceStatus _status(InvoiceStatus status) => switch (status) {
    InvoiceStatus.unpaid => GetPaidInvoiceStatus.unpaid,
    InvoiceStatus.inProgress => GetPaidInvoiceStatus.inProgress,
    InvoiceStatus.partiallyPaid => GetPaidInvoiceStatus.partiallyPaid,
    InvoiceStatus.paid => GetPaidInvoiceStatus.paid,
    InvoiceStatus.underpaid => GetPaidInvoiceStatus.underpaid,
    InvoiceStatus.overpaid => GetPaidInvoiceStatus.overpaid,
    InvoiceStatus.expired => GetPaidInvoiceStatus.expired,
    InvoiceStatus.cancelled => GetPaidInvoiceStatus.cancelled,
    InvoiceStatus.unsupported => GetPaidInvoiceStatus.unsupported,
  };

  GetPaidInvoiceSettlementState _settlementState(
    InvoiceSettlementState state,
  ) => switch (state) {
    InvoiceSettlementState.none => GetPaidInvoiceSettlementState.none,
    InvoiceSettlementState.pending => GetPaidInvoiceSettlementState.pending,
    InvoiceSettlementState.settled => GetPaidInvoiceSettlementState.settled,
    InvoiceSettlementState.problem => GetPaidInvoiceSettlementState.problem,
  };

  GetPaidInvoiceRail _rail(PaymentMethod rail) => switch (rail) {
    PaymentMethod.btc => GetPaidInvoiceRail.bitcoin,
    PaymentMethod.lightning => GetPaidInvoiceRail.lightning,
    PaymentMethod.liquid => GetPaidInvoiceRail.liquid,
  };

  GetPaidInvoicePaymentEventState _eventState(
    InvoicePaymentEventState state,
  ) => switch (state) {
    InvoicePaymentEventState.pending => GetPaidInvoicePaymentEventState.pending,
    InvoicePaymentEventState.confirming =>
      GetPaidInvoicePaymentEventState.confirming,
    InvoicePaymentEventState.settled => GetPaidInvoicePaymentEventState.settled,
    InvoicePaymentEventState.problem => GetPaidInvoicePaymentEventState.problem,
  };

  GetPaidInvoicePaymentProblem _paymentProblem(InvoicePaymentProblem problem) =>
      switch (problem) {
        InvoicePaymentProblem.evicted => GetPaidInvoicePaymentProblem.evicted,
        InvoicePaymentProblem.reorged => GetPaidInvoicePaymentProblem.reorged,
        InvoicePaymentProblem.conflicted =>
          GetPaidInvoicePaymentProblem.conflicted,
        InvoicePaymentProblem.replaced => GetPaidInvoicePaymentProblem.replaced,
        InvoicePaymentProblem.unknown => GetPaidInvoicePaymentProblem.unknown,
      };
}
