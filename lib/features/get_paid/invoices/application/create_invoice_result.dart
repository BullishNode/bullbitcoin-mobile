import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_url.dart';

class CreateInvoiceResult {
  final InvoiceId invoiceId;
  final InvoiceUrl shareUrl;

  const CreateInvoiceResult({required this.invoiceId, required this.shareUrl});
}
