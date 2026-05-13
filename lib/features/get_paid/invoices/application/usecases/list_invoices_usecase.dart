import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_identity_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';

class ListInvoicesUsecase {
  final InvoicesPayServicePort _invoiceService;
  final InvoicesIdentityPort _invoiceIdentity;

  const ListInvoicesUsecase({
    required InvoicesPayServicePort invoiceService,
    required InvoicesIdentityPort invoiceIdentity,
  }) : _invoiceService = invoiceService,
       _invoiceIdentity = invoiceIdentity;

  Future<List<Invoice>> execute({required ListInvoicesCommand command}) async {
    final handle = await _invoiceIdentity.getSigningHandle();
    return _invoiceService.listInvoices(command: command, handle: handle);
  }
}
