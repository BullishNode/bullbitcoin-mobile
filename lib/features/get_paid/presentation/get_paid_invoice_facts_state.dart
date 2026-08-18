import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';

/// The invoice-state read behind a Get Paid transaction detail card.
///
/// The four states are distinct on purpose. [GetPaidInvoiceFactsInitial] means no
/// read applies (a Lightning Address receipt carries no invoice id);
/// [GetPaidInvoiceFactsFailure] means a read was attempted and failed. Collapsing
/// those two is what would let an unreadable invoice render as an invoice-less
/// payment.
sealed class GetPaidInvoiceFactsState {
  const GetPaidInvoiceFactsState();
}

/// No invoice read applies to this entry.
final class GetPaidInvoiceFactsInitial extends GetPaidInvoiceFactsState {
  const GetPaidInvoiceFactsInitial();
}

/// The invoice state is being read.
final class GetPaidInvoiceFactsLoading extends GetPaidInvoiceFactsState {
  const GetPaidInvoiceFactsLoading();
}

/// The invoice state, as the invoices boundary reported it.
final class GetPaidInvoiceFactsData extends GetPaidInvoiceFactsState {
  final GetPaidInvoiceFacts invoice;
  final bool isRefreshing;
  final bool refreshFailed;

  const GetPaidInvoiceFactsData(
    this.invoice, {
    this.isRefreshing = false,
    this.refreshFailed = false,
  });
}

/// The read was attempted and failed; the card says so.
final class GetPaidInvoiceFactsFailure extends GetPaidInvoiceFactsState {
  final GetPaidFailure failure;

  const GetPaidInvoiceFactsFailure(this.failure);
}
