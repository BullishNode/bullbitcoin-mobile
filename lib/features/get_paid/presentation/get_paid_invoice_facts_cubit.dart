import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the invoice-state read for one Get Paid transaction detail card.
///
/// The card renders whichever state this holds; it never resolves the invoices
/// boundary itself and never drops a failure. An entry with no invoice id is a
/// no-op that stays [GetPaidInvoiceFactsInitial] — nothing is read, and nothing
/// is claimed.
class GetPaidInvoiceFactsCubit extends Cubit<GetPaidInvoiceFactsState> {
  final LookUpGetPaidInvoiceFactsUsecase _lookUpInvoiceFacts;

  GetPaidInvoiceFactsCubit({required this._lookUpInvoiceFacts})
    : super(const GetPaidInvoiceFactsInitial());

  Future<void> load({required String? invoiceId}) async {
    if (invoiceId == null) return;
    emit(const GetPaidInvoiceFactsLoading());
    final result = await _lookUpInvoiceFacts.execute(invoiceId: invoiceId);
    if (isClosed) return;
    emit(switch (result) {
      Ok(:final value) => GetPaidInvoiceFactsData(value),
      Err(:final failure) => GetPaidInvoiceFactsFailure(failure),
    });
  }
}
