import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/entities/invoice_status_snapshot.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'invoice_detail_state.freezed.dart';

@freezed
sealed class InvoiceDetailState with _$InvoiceDetailState {
  const factory InvoiceDetailState({
    InvoiceId? invoiceId,
    String? nymOwner,
    InvoiceStatusSnapshot? snapshot,
    CancelInvoiceResult? cancelResult,
    @Default(false) bool isLoading,
    @Default(false) bool isCancelling,
    String? error,
  }) = _InvoiceDetailState;

  const InvoiceDetailState._();

  bool get hasInvoice => invoiceId != null;
  bool get isBusy => isLoading || isCancelling;
}
