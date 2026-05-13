import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';

class CancelInvoiceCommand {
  final InvoiceId invoiceId;
  final String? nymOwner;

  const CancelInvoiceCommand({required this.invoiceId, required this.nymOwner});
}
