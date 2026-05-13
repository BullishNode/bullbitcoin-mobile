import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';

class ListInvoicesCommand {
  final DateTime? since;
  final int limit;
  final InvoiceStatus? status;

  ListInvoicesCommand({
    required this.since,
    this.limit = 100,
    required this.status,
  }) {
    if (limit < 1 || limit > 100) {
      throw const InvoicesValidationError('limit must be between 1 and 100');
    }
  }
}
