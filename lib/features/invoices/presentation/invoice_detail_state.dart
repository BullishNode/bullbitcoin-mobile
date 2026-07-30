import 'package:bb_mobile/features/invoices/public/invoices_facade.dart';

enum InvoiceDetailStatus { loading, loaded, error }

/// The invoice detail state. [snapshot] is the public status shape; the cancel
/// result is kept SEPARATELY ([cancelFinalStatus]) so the two are never
/// conflated (§3.11). [invoice] is the optional list row the detail was opened
/// from (for fields the status endpoint does not carry, e.g. the share URL /
/// recipient).
class InvoiceDetailState {
  final InvoiceDetailStatus status;
  final Invoice? invoice;
  final InvoiceStatusSnapshot? snapshot;
  final InvoicesFailure? failure;
  final InvoicesFailure? authenticatedInvoiceFailure;
  final bool authenticatedInvoiceRefreshing;
  final bool authenticatedPaymentEvidenceSeen;
  final PrivateInvoiceLink? privateLink;
  final bool privateLinkLookupComplete;
  final List<InvoiceFallbackSupervision> fallbackSupervisions;
  final bool fallbackSupervisionOverflow;
  final InvoicesFailure? fallbackSupervisionFailure;

  final PaymentMethod? selectedQuoteRail;
  final InvoiceQuote? quote;
  final bool quoteRefreshing;
  final InvoicesFailure? quoteFailure;

  final bool cancelling;
  final InvoiceStatus? cancelFinalStatus;
  final InvoicesFailure? cancelFailure;

  const InvoiceDetailState({
    this.status = InvoiceDetailStatus.loading,
    this.invoice,
    this.snapshot,
    this.failure,
    this.authenticatedInvoiceFailure,
    this.authenticatedInvoiceRefreshing = false,
    this.authenticatedPaymentEvidenceSeen = false,
    this.privateLink,
    this.privateLinkLookupComplete = false,
    this.fallbackSupervisions = const [],
    this.fallbackSupervisionOverflow = false,
    this.fallbackSupervisionFailure,
    this.selectedQuoteRail,
    this.quote,
    this.quoteRefreshing = false,
    this.quoteFailure,
    this.cancelling = false,
    this.cancelFinalStatus,
    this.cancelFailure,
  });

  /// The current effective status: the settled cancel status wins over the
  /// polled snapshot once a cancel has completed.
  InvoiceStatus? get effectiveStatus => cancelFinalStatus ?? snapshot?.status;

  InvoiceFallbackState? get fallbackState =>
      mostUrgentInvoiceFallbackState(fallbackSupervisions);

  bool get isTerminal {
    // A terminal public invoice with an unresolved authenticated projection
    // must continue polling. Treating an empty projection as complete after a
    // transient failure would permanently stop supervision updates.
    if (fallbackSupervisionFailure != null) return false;
    if (authenticatedInvoiceFailure != null || authenticatedInvoiceRefreshing) {
      return false;
    }
    // A cancel response is not a settlement snapshot. A cancelled invoice
    // can still have a payment race or unresolved settlement evidence, so
    // polling may stop only after the status endpoint reports completion.
    final invoiceTerminal = snapshot?.isMonitoringComplete ?? false;
    if (!invoiceTerminal) return false;
    if (fallbackSupervisions.isEmpty) return true;
    return fallbackSupervisions.every(
      (item) => item.state == InvoiceFallbackState.settled,
    );
  }

  /// Cancel is offered only while unpaid (DG-I5), and never mid-cancel.
  bool get canCancel =>
      !cancelling &&
      cancelFinalStatus == null &&
      !hasAuthenticatedPaymentEvidence &&
      (snapshot?.isCancellable ?? false);

  bool get hasAuthenticatedPaymentEvidence =>
      authenticatedPaymentEvidenceSeen ||
      (invoice?.hasPaymentEvidence ?? false);

  bool acceptsInitialPayment(DateTime now) =>
      !hasAuthenticatedPaymentEvidence &&
      (snapshot?.acceptsInitialPayment(now) ?? false);

  bool hasUsableQuote(DateTime now) =>
      quote != null && !quote!.isExpired(now) && !quoteRefreshing;

  InvoiceDetailState copyWith({
    InvoiceDetailStatus? status,
    Invoice? invoice,
    InvoiceStatusSnapshot? snapshot,
    InvoicesFailure? failure,
    InvoicesFailure? authenticatedInvoiceFailure,
    bool? authenticatedInvoiceRefreshing,
    bool? authenticatedPaymentEvidenceSeen,
    PrivateInvoiceLink? privateLink,
    bool? privateLinkLookupComplete,
    List<InvoiceFallbackSupervision>? fallbackSupervisions,
    bool? fallbackSupervisionOverflow,
    InvoicesFailure? fallbackSupervisionFailure,
    PaymentMethod? selectedQuoteRail,
    InvoiceQuote? quote,
    bool? quoteRefreshing,
    InvoicesFailure? quoteFailure,
    bool? cancelling,
    InvoiceStatus? cancelFinalStatus,
    InvoicesFailure? cancelFailure,
    bool clearFailure = false,
    bool clearAuthenticatedInvoiceFailure = false,
    bool clearFallbackSupervisionFailure = false,
    bool clearQuote = false,
    bool clearQuoteFailure = false,
    bool clearCancelFailure = false,
  }) {
    return InvoiceDetailState(
      status: status ?? this.status,
      invoice: invoice ?? this.invoice,
      snapshot: snapshot ?? this.snapshot,
      failure: clearFailure ? null : failure ?? this.failure,
      authenticatedInvoiceFailure: clearAuthenticatedInvoiceFailure
          ? null
          : authenticatedInvoiceFailure ?? this.authenticatedInvoiceFailure,
      authenticatedInvoiceRefreshing:
          authenticatedInvoiceRefreshing ?? this.authenticatedInvoiceRefreshing,
      authenticatedPaymentEvidenceSeen:
          authenticatedPaymentEvidenceSeen ??
          this.authenticatedPaymentEvidenceSeen,
      privateLink: privateLink ?? this.privateLink,
      privateLinkLookupComplete:
          privateLinkLookupComplete ?? this.privateLinkLookupComplete,
      fallbackSupervisions: fallbackSupervisions ?? this.fallbackSupervisions,
      fallbackSupervisionOverflow:
          fallbackSupervisionOverflow ?? this.fallbackSupervisionOverflow,
      fallbackSupervisionFailure: clearFallbackSupervisionFailure
          ? null
          : fallbackSupervisionFailure ?? this.fallbackSupervisionFailure,
      selectedQuoteRail: selectedQuoteRail ?? this.selectedQuoteRail,
      quote: clearQuote ? null : quote ?? this.quote,
      quoteRefreshing: quoteRefreshing ?? this.quoteRefreshing,
      quoteFailure: clearQuoteFailure
          ? null
          : quoteFailure ?? this.quoteFailure,
      cancelling: cancelling ?? this.cancelling,
      cancelFinalStatus: cancelFinalStatus ?? this.cancelFinalStatus,
      cancelFailure: clearCancelFailure
          ? null
          : cancelFailure ?? this.cancelFailure,
    );
  }
}
