import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/list_get_paid_transactions_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidTransactionHistoryCubit
    extends Cubit<GetPaidTransactionHistoryState> {
  static const int pageSize = 20;

  final ListGetPaidTransactionsUsecase _listTransactions;

  /// Optional, mainnet-only fiat-settlement seam used to derive the EXPECTED
  /// settlement kind per product for rows the server did not classify. Both are
  /// null in isolated tests / environments where fiat settlement is not wired,
  /// in which case rows fall back to the rail label.
  final FiatSettlementFacade? _fiatSettlement;
  final GetSettingsUsecase? _getSettings;
  int _generation = 0;
  Set<String> _seenCursors = const {};

  GetPaidTransactionHistoryCubit({
    required this._listTransactions,
    this._fiatSettlement,
    this._getSettings,
  }) : super(const GetPaidTransactionHistoryState());

  Future<void> load() => refresh();

  Future<void> refresh() async {
    final generation = ++_generation;
    _seenCursors = {''};
    emit(
      const GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loading,
      ),
    );
    // The expected-kind config is read once per load, concurrently with the
    // first page, and never blocks or fails the transaction list.
    final expectedKindsFuture = _loadExpectedSettlementKinds();
    final result = await _listTransactions.execute(cursor: '', limit: pageSize);
    final expectedKinds = await expectedKindsFuture;
    if (_isStale(generation)) return;
    switch (result) {
      case Ok(:final value):
        emit(
          GetPaidTransactionHistoryState(
            status: GetPaidTransactionHistoryStatus.loaded,
            transactions: value.transactions,
            nextCursor: value.nextCursor,
            expectedSettlementKinds: expectedKinds,
          ),
        );
      case Err(:final failure):
        emit(
          GetPaidTransactionHistoryState(
            status: GetPaidTransactionHistoryStatus.failure,
            failure: failure,
          ),
        );
    }
  }

  /// The per-product expected settlement kind, or null when the feature is not
  /// wired, the environment is not mainnet, or the config read failed. Never
  /// throws: an unavailable config simply drops back to the rail label.
  Future<Map<FiatSettlementProduct, FiatSettlementMode>?>
  _loadExpectedSettlementKinds() async {
    final facade = _fiatSettlement;
    final getSettings = _getSettings;
    if (facade == null || getSettings == null) return null;
    try {
      final settings = await getSettings.execute();
      if (settings.environment != Environment.mainnet) return null;
      final result = await facade.configuration();
      switch (result) {
        case Ok(:final value):
          return {
            for (final product in FiatSettlementProduct.values)
              product: value.configFor(product).mode,
          };
        case Err():
          return null;
      }
    } on Exception catch (error, trace) {
      log.warning(
        'Get Paid history expected-settlement-kind lookup failed',
        error: error,
        trace: trace,
      );
      return null;
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (state.status != GetPaidTransactionHistoryStatus.loaded ||
        cursor == null ||
        state.isLoadingMore) {
      return;
    }

    final generation = _generation;
    if (_seenCursors.contains(cursor)) {
      emit(
        state.copyWith(
          clearNextCursor: true,
          isLoadingMore: false,
          loadMoreFailed: true,
        ),
      );
      return;
    }
    emit(state.copyWith(isLoadingMore: true, loadMoreFailed: false));
    final result = await _listTransactions.execute(
      cursor: cursor,
      limit: pageSize,
    );
    if (_isStale(generation)) return;
    switch (result) {
      case Ok(:final value):
        final pageCursors = {..._seenCursors, cursor};
        if (value.nextCursor != null &&
            pageCursors.contains(value.nextCursor)) {
          emit(
            state.copyWith(
              clearNextCursor: true,
              isLoadingMore: false,
              loadMoreFailed: true,
            ),
          );
          return;
        }
        _seenCursors = pageCursors;
        emit(
          state.copyWith(
            transactions: _mergeByStableKey(
              state.transactions,
              value.transactions,
            ),
            nextCursor: value.nextCursor,
            clearNextCursor: value.nextCursor == null,
            isLoadingMore: false,
            loadMoreFailed: false,
          ),
        );
      case Err():
        emit(state.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }

  List<GetPaidTransaction> _mergeByStableKey(
    List<GetPaidTransaction> current,
    List<GetPaidTransaction> next,
  ) {
    final merged = current.toList();
    final indexByKey = <String, int>{
      for (var index = 0; index < merged.length; index++)
        merged[index].stableKey: index,
    };
    for (final transaction in next) {
      final existing = indexByKey[transaction.stableKey];
      if (existing == null) {
        indexByKey[transaction.stableKey] = merged.length;
        merged.add(transaction);
      } else {
        merged[existing] = transaction;
      }
    }
    return List.unmodifiable(merged);
  }

  bool _isStale(int generation) => isClosed || generation != _generation;
}
