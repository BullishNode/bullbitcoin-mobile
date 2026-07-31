import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';

class GetPaidTransactionDetailState {
  final GetPaidTransaction transaction;
  final bool isRefreshing;
  final bool refreshFailed;

  const GetPaidTransactionDetailState({
    required this.transaction,
    this.isRefreshing = false,
    this.refreshFailed = false,
  });

  GetPaidTransactionDetailState copyWith({
    GetPaidTransaction? transaction,
    bool? isRefreshing,
    bool? refreshFailed,
  }) {
    return GetPaidTransactionDetailState(
      transaction: transaction ?? this.transaction,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      refreshFailed: refreshFailed ?? this.refreshFailed,
    );
  }
}
