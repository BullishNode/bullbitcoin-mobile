import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'invoices_list_state.freezed.dart';

@freezed
sealed class InvoicesListState with _$InvoicesListState {
  const factory InvoicesListState({
    @Default([]) List<Invoice> invoices,
    @Default(1) int page,
    @Default(100) int pageSize,
    @Default(false) bool hasMore,
    InvoiceStatus? statusFilter,
    @Default(false) bool isLoading,
    String? error,
  }) = _InvoicesListState;

  const InvoicesListState._();

  List<Invoice> get filteredInvoices {
    final filter = statusFilter;
    if (filter == null) return invoices;
    return invoices.where((invoice) => invoice.status == filter).toList();
  }
}
