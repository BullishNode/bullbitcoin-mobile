import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the invoice-state read for one Get Paid transaction detail card.
///
/// The card renders whichever state this holds; it never resolves the invoices boundary itself and never drops a failure. An entry with no invoice id is a no-op that stays [GetPaidInvoiceFactsInitial] — nothing is read, and nothing is claimed.
class GetPaidInvoiceFactsCubit extends Cubit<GetPaidInvoiceFactsState> {
  final LookUpGetPaidInvoiceFactsUsecase _lookUpInvoiceFacts;
  int _loadOperation = 0;
  String? _invoiceId;

  GetPaidInvoiceFactsCubit({required this._lookUpInvoiceFacts})
    : super(const GetPaidInvoiceFactsInitial());

  Future<void> load({required String? invoiceId}) async {
    if (invoiceId == null) return;
    final operation = ++_loadOperation;
    _invoiceId = invoiceId;
    final retained = state is GetPaidInvoiceFactsData
        ? (state as GetPaidInvoiceFactsData).invoice
        : null;
    emit(
      retained == null
          ? const GetPaidInvoiceFactsLoading()
          : GetPaidInvoiceFactsData(retained, isRefreshing: true),
    );
    final result = await _lookUpInvoiceFacts.execute(invoiceId: invoiceId);
    if (isClosed || operation != _loadOperation) return;
    switch (result) {
      case Ok(:final value):
        emit(GetPaidInvoiceFactsData(value));
      case Err(:final failure):
        emit(
          retained == null
              ? GetPaidInvoiceFactsFailure(failure)
              : GetPaidInvoiceFactsData(retained, refreshFailed: true),
        );
    }
  }

  Future<void> retry() => load(invoiceId: _invoiceId);
}
