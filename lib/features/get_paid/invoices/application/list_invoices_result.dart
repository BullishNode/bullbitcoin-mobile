import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';

class ListInvoicesResult {
  final List<Invoice> invoices;
  final int page;
  final int pageSize;
  final bool hasMore;

  const ListInvoicesResult({
    required this.invoices,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });
}
