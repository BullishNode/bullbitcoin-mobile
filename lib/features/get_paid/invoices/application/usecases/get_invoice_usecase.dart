import 'package:bb_mobile/features/get_paid/invoices/application/ports/invoices_pay_service_port.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';

class GetInvoiceUsecase {
  final InvoicesPayServicePort _invoiceService;

  const GetInvoiceUsecase({required InvoicesPayServicePort invoiceService})
    : _invoiceService = invoiceService;

  Future<InvoiceStatusSnapshot> execute({required InvoiceId id}) {
    return _invoiceService.getInvoiceStatus(id: id);
  }
}
