import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';

class CancelInvoiceResult {
  final InvoiceId invoiceId;
  final InvoiceStatus status;

  const CancelInvoiceResult({required this.invoiceId, required this.status});
}
