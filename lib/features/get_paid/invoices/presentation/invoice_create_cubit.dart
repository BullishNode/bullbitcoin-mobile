import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/create_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_create_state.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_error_message.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_expiry_days.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InvoiceCreateCubit extends Cubit<InvoiceCreateState> {
  final CreateInvoiceUsecase _createInvoice;

  InvoiceCreateCubit({
    required CreateInvoiceUsecase createInvoice,
    DateTime? initialExpiresAt,
  }) : _createInvoice = createInvoice,
       super(
         InvoiceCreateState(
           expiresAt:
               initialExpiresAt ??
               DateTime.now().toUtc().add(const Duration(days: 1)),
         ),
       );

  void setAmountSat(int? value) {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        amountSat: value,
        fiatAmountMinor: null,
        fiatCurrency: null,
        result: null,
        error: null,
      ),
    );
  }

  void setFiatAmount({required int? minor, required String? currency}) {
    if (state.isBusy) return;
    emit(
      state.copyWith(
        amountSat: null,
        fiatAmountMinor: minor,
        fiatCurrency: currency,
        result: null,
        error: null,
      ),
    );
  }

  void setPublicDescription(String value) {
    if (state.isBusy) return;
    emit(state.copyWith(publicDescription: value, result: null, error: null));
  }

  void setRecipientName(String value) {
    if (state.isBusy) return;
    emit(state.copyWith(recipientName: value, result: null, error: null));
  }

  void setInvoiceNumber(String value) {
    if (state.isBusy) return;
    emit(state.copyWith(invoiceNumber: value, result: null, error: null));
  }

  void setAcceptBtc(bool value) {
    if (state.isBusy) return;
    emit(state.copyWith(acceptBtc: value, result: null, error: null));
  }

  void setAcceptLn(bool value) {
    if (state.isBusy) return;
    emit(state.copyWith(acceptLn: value, result: null, error: null));
  }

  void setAcceptLiquid(bool value) {
    if (state.isBusy) return;
    emit(state.copyWith(acceptLiquid: value, result: null, error: null));
  }

  void setExpiresAt(DateTime value) {
    if (state.isBusy) return;
    emit(state.copyWith(expiresAt: value, result: null, error: null));
  }

  void clearError() {
    if (state.isBusy || state.error == null) return;
    emit(state.copyWith(error: null));
  }

  void setLinkToPageNym(String value) {
    if (state.isBusy) return;
    emit(state.copyWith(linkToPageNym: value, result: null, error: null));
  }

  void setPrivateMemo(String value) {
    if (state.isBusy) return;
    emit(state.copyWith(privateMemo: value, result: null, error: null));
  }

  Future<void> submit({DateTime? now}) async {
    if (state.isBusy) return;
    emit(state.copyWith(isSubmitting: true, result: null, error: null));
    try {
      final submitTime = now ?? DateTime.now().toUtc();
      final command = CreateInvoiceCommand(
        amountSat: state.amountSat,
        fiatAmountMinor: state.fiatAmountMinor,
        fiatCurrency: _blankToNull(state.fiatCurrency),
        publicDescription: _blankToNull(state.publicDescription),
        recipientName: _blankToNull(state.recipientName),
        invoiceNumber: _blankToNull(state.invoiceNumber),
        acceptBtc: state.acceptBtc,
        acceptLn: state.acceptLn,
        acceptLiquid: state.acceptLiquid,
        expiresAt: _expiresAtForSubmit(submitTime),
        linkToPageNym: _blankToNull(state.linkToPageNym),
        privateMemo: _blankToNull(state.privateMemo),
        now: submitTime,
      );
      final result = await _createInvoice.execute(command: command);
      if (isClosed) return;
      emit(state.copyWith(isSubmitting: false, result: result, error: null));
    } on InvoicesApplicationError catch (e) {
      if (isClosed) return;
      log.warning('Invoice create application error: ${e.message}', error: e);
      emit(state.copyWith(isSubmitting: false, error: invoiceErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Invoice create failed', error: e);
      emit(
        state.copyWith(
          isSubmitting: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  DateTime _expiresAtForSubmit(DateTime now) {
    return invoiceExpiresAtForDays(
      days: invoiceExpiryDaysFrom(expiresAt: state.expiresAt, now: now),
      now: now,
    );
  }
}
