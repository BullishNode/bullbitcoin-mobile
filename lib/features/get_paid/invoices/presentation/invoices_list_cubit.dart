import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/invoices_application_error.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_command.dart';
import 'package:bb_mobile/features/get_paid/invoices/application/usecases/list_invoices_usecase.dart';
import 'package:bb_mobile/features/get_paid/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/get_paid/invoices/presentation/invoices_list_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InvoicesListCubit extends Cubit<InvoicesListState> {
  final ListInvoicesUsecase _listInvoices;

  InvoicesListCubit({required ListInvoicesUsecase listInvoices})
    : _listInvoices = listInvoices,
      super(const InvoicesListState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final invoices = await _listInvoices.execute(
        command: ListInvoicesCommand(since: null, status: null),
      );
      if (isClosed) return;
      emit(state.copyWith(invoices: invoices, isLoading: false, error: null));
    } on InvoicesApplicationError catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isLoading: false, error: e.message));
    } on Exception catch (e) {
      if (isClosed) return;
      log.warning('Invoices list load failed', error: e);
      emit(
        state.copyWith(
          isLoading: false,
          error: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  Future<void> refresh() => load();

  void setStatusFilter(InvoiceStatus? status) {
    emit(state.copyWith(statusFilter: status, error: null));
  }
}
