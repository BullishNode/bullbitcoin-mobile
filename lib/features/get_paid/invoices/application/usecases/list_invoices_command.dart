import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';

class ListInvoicesCommand {
  final int page;
  final int pageSize;
  final InvoiceStatus? status;

  ListInvoicesCommand({
    this.page = 1,
    this.pageSize = 100,
    required this.status,
  }) {
    if (page < 1 || page > 1000) {
      throw const InvoicesValidationError('page must be between 1 and 1000');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw const InvoicesValidationError('pageSize must be between 1 and 100');
    }
  }
}
