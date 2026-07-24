import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';

enum GetPaidTransactionHistoryStatus { initial, loading, loaded, failure }

class GetPaidTransactionHistoryState {
  final GetPaidTransactionHistoryStatus status;
  final List<GetPaidTransaction> transactions;
  final String? nextCursor;
  final GetPaidFailure? failure;
  final bool isLoadingMore;
  final bool loadMoreFailed;

  /// The settlement kind EXPECTED per product, derived from the mainnet
  /// fiat-settlement configuration and fetched once per screen load. Null when
  /// the feature is not wired, off testnet, or the config read failed — in
  /// which case rows fall back to the rail label, never a guessed kind.
  final Map<FiatSettlementProduct, FiatSettlementMode>? expectedSettlementKinds;

  const GetPaidTransactionHistoryState({
    this.status = GetPaidTransactionHistoryStatus.initial,
    this.transactions = const [],
    this.nextCursor,
    this.failure,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
    this.expectedSettlementKinds,
  });

  bool get isEmpty =>
      status == GetPaidTransactionHistoryStatus.loaded && transactions.isEmpty;

  bool get hasMore => nextCursor != null;

  GetPaidTransactionHistoryState copyWith({
    GetPaidTransactionHistoryStatus? status,
    List<GetPaidTransaction>? transactions,
    String? nextCursor,
    bool clearNextCursor = false,
    GetPaidFailure? failure,
    bool clearFailure = false,
    bool? isLoadingMore,
    bool? loadMoreFailed,
    Map<FiatSettlementProduct, FiatSettlementMode>? expectedSettlementKinds,
  }) {
    return GetPaidTransactionHistoryState(
      status: status ?? this.status,
      transactions: transactions ?? this.transactions,
      nextCursor: clearNextCursor ? null : nextCursor ?? this.nextCursor,
      failure: clearFailure ? null : failure ?? this.failure,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      expectedSettlementKinds:
          expectedSettlementKinds ?? this.expectedSettlementKinds,
    );
  }
}
