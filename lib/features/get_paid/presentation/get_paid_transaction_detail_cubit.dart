import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_transaction_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_detail_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Owns the live receipt projection shown by one Get Paid detail screen.
///
/// A failed refresh deliberately retains the last verified receipt. The state
/// marks that retained projection as stale instead of replacing it with an
/// empty/error-only screen.
class GetPaidTransactionDetailCubit
    extends Cubit<GetPaidTransactionDetailState> {
  final LookUpGetPaidTransactionUsecase _lookUpTransaction;
  int _refreshOperation = 0;

  GetPaidTransactionDetailCubit(
    this._lookUpTransaction, {
    required GetPaidTransaction initialTransaction,
  }) : super(GetPaidTransactionDetailState(transaction: initialTransaction));

  Future<void> refresh() async {
    final operation = ++_refreshOperation;
    final current = state.transaction;
    emit(state.copyWith(isRefreshing: true, refreshFailed: false));

    final result = await _lookUpTransaction.execute(
      source: current.source,
      transactionId: current.transactionId,
    );
    if (isClosed || operation != _refreshOperation) return;

    switch (result) {
      case Ok(:final value):
        emit(
          GetPaidTransactionDetailState(
            transaction: value,
            isRefreshing: false,
          ),
        );
      case Err():
        emit(state.copyWith(isRefreshing: false, refreshFailed: true));
    }
  }
}
