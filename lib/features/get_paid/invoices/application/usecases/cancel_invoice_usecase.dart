import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';

class CancelInvoiceUsecase {
  final InvoicesPayServicePort _invoiceService;
  final InvoicesIdentityPort _invoiceIdentity;

  const CancelInvoiceUsecase({
    required InvoicesPayServicePort invoiceService,
    required InvoicesIdentityPort invoiceIdentity,
  }) : _invoiceService = invoiceService,
       _invoiceIdentity = invoiceIdentity;

  Future<CancelInvoiceResult> execute({
    required CancelInvoiceCommand command,
  }) async {
    final handle = await _invoiceIdentity.getSigningHandle();
    return _invoiceService.cancelInvoice(command: command, handle: handle);
  }
}
