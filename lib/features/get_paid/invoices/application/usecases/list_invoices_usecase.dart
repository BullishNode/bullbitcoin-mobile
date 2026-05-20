import 'package:bb_mobile/features/get_paid/invoices/application/list_invoices_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';

class ListInvoicesUsecase {
  final InvoicesPayServicePort _invoiceService;
  final InvoicesIdentityPort _invoiceIdentity;

  const ListInvoicesUsecase({
    required InvoicesPayServicePort invoiceService,
    required InvoicesIdentityPort invoiceIdentity,
  }) : _invoiceService = invoiceService,
       _invoiceIdentity = invoiceIdentity;

  Future<ListInvoicesResult> execute({
    required ListInvoicesCommand command,
  }) async {
    final handle = await _invoiceIdentity.getSigningHandle();
    final result = await _invoiceService.listInvoices(
      command: command,
      handle: handle,
    );
    return ListInvoicesResult(
      invoices: result.invoices
          .where((invoice) => !_isHiddenCheckoutInvoice(invoice))
          .toList(growable: false),
      page: result.page,
      pageSize: result.pageSize,
      hasMore: result.hasMore,
    );
  }

  bool _isHiddenCheckoutInvoice(Invoice invoice) {
    if (invoice.origin != 'checkout') return false;
    return invoice.status == InvoiceStatus.unpaid ||
        invoice.status == InvoiceStatus.expired;
  }
}
