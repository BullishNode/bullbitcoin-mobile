import 'package:bb_mobile/features/get_paid/invoices/application/create_invoice_result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'invoice_create_state.freezed.dart';

@freezed
sealed class InvoiceCreateState with _$InvoiceCreateState {
  const factory InvoiceCreateState({
    int? amountSat,
    int? fiatAmountMinor,
    String? fiatCurrency,
    @Default('') String publicDescription,
    @Default('') String recipientName,
    @Default('') String invoiceNumber,
    @Default(true) bool acceptBtc,
    @Default(true) bool acceptLn,
    @Default(false) bool acceptLiquid,
    required DateTime expiresAt,
    @Default('') String linkToPageNym,
    @Default('') String privateMemo,
    @Default(false) bool isSubmitting,
    CreateInvoiceResult? result,
    String? error,
  }) = _InvoiceCreateState;

  const InvoiceCreateState._();

  bool get created => result != null;
  bool get isBusy => isSubmitting;
}
