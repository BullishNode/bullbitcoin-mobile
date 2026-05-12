import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/cancel_invoice_result.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/cancel_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/get_invoice_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/value_objects/invoice_id.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_detail_state.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoice_error_message.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InvoiceDetailCubit extends Cubit<InvoiceDetailState> {
  final GetInvoiceUsecase _getInvoice;
  final CancelInvoiceUsecase _cancelInvoice;

  InvoiceDetailCubit({
    required GetInvoiceUsecase getInvoice,
    required CancelInvoiceUsecase cancelInvoice,
  }) : _getInvoice = getInvoice,
       _cancelInvoice = cancelInvoice,
       super(const InvoiceDetailState());

  Future<void> load({required InvoiceId id, String? nymOwner}) async {
    final isDifferentInvoice = state.invoiceId != id;
    emit(
      state.copyWith(
        invoiceId: id,
        nymOwner: nymOwner,
        snapshot: isDifferentInvoice ? null : state.snapshot,
        isLoading: true,
        error: null,
        cancelResult: null,
      ),
    );
    try {
      final snapshot = await _getInvoice.execute(id: id);
      if (isClosed) return;
      emit(state.copyWith(snapshot: snapshot, isLoading: false, error: null));
    } on InvoicesApplicationError catch (e) {
      if (isClosed) return;
      log.warning('Invoice detail application error', error: e);
      emit(state.copyWith(isLoading: false, error: invoiceErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Invoice detail load failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> refresh() async {
    final id = state.invoiceId;
    if (id == null) return;
    await load(id: id, nymOwner: state.nymOwner);
  }

  Future<CancelInvoiceResult?> cancel() async {
    final id = state.invoiceId;
    if (id == null || state.isBusy) return null;
    emit(state.copyWith(isCancelling: true, error: null, cancelResult: null));
    try {
      final result = await _cancelInvoice.execute(
        command: CancelInvoiceCommand(invoiceId: id, nymOwner: state.nymOwner),
      );
      if (isClosed) return result;
      emit(
        state.copyWith(isCancelling: false, cancelResult: result, error: null),
      );
      return result;
    } on InvoicesApplicationError catch (e) {
      if (isClosed) return null;
      log.warning('Invoice cancel application error', error: e);
      emit(state.copyWith(isCancelling: false, error: invoiceErrorMessage(e)));
    } on Exception catch (e) {
      if (isClosed) return null;
      log.warning('Invoice cancel failed', error: e);
      emit(
        state.copyWith(
          isCancelling: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
    return null;
  }
}
