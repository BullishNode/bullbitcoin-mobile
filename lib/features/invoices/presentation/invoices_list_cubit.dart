// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_commands.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice_results.dart';
import 'package:bb_mobile/features/invoices/domain/entities/invoice.dart';
import 'package:bb_mobile/features/invoices/domain/invoices_failure.dart';
import 'package:bb_mobile/features/invoices/domain/primitives/invoice_status.dart';
import 'package:bb_mobile/features/invoices/presentation/invoices_list_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef ListMerchantInvoices =
    Future<Result<ListInvoicesResult, InvoicesFailure>> Function(
      ListInvoicesCommand command,
    );

/// Drives the invoices list. It loads the npub's invoices with NO server-side
/// status filter (the filter is applied client-side over the loaded set), and
/// holds `hasMore` in state.
class InvoicesListCubit extends Cubit<InvoicesListState> {
  final ListMerchantInvoices _list;
  int _requestGeneration = 0;

  InvoicesListCubit({required ListMerchantInvoices list})
    : _list = list,
      super(const InvoicesListState());

  Future<void> load() => _fetch();

  Future<void> refresh() => _fetch();

  Future<void> loadMore() async {
    if (state.status != InvoicesListStatus.loaded ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    final generation = _requestGeneration;
    emit(state.copyWith(loadingMore: true, loadMoreFailed: false));
    final result = await _list(ListInvoicesCommand(page: state.page + 1));
    if (isClosed || generation != _requestGeneration) return;
    switch (result) {
      case Ok(:final value):
        final byId = <String, Invoice>{
          for (final invoice in state.invoices) invoice.id.value: invoice,
          for (final invoice in value.invoices) invoice.id.value: invoice,
        };
        emit(
          state.copyWith(
            invoices: List.unmodifiable(byId.values),
            page: value.page,
            hasMore: value.hasMore,
            loadingMore: false,
            loadMoreFailed: false,
            fallbackSupervisionUnavailable:
                state.fallbackSupervisionUnavailable ||
                value.fallbackSupervisionUnavailable,
            fallbackSupervisionOverflow:
                state.fallbackSupervisionOverflow ||
                value.fallbackSupervisionOverflow,
          ),
        );
      case Err():
        emit(state.copyWith(loadingMore: false, loadMoreFailed: true));
    }
  }

  /// Client-side status filter (no wire call). Passing null clears it.
  void setFilter(InvoiceStatus? filter) {
    emit(
      filter == null
          ? state.copyWith(clearFilter: true)
          : state.copyWith(filter: filter),
    );
  }

  Future<void> _fetch() async {
    final generation = ++_requestGeneration;
    emit(
      state.copyWith(status: InvoicesListStatus.loading, clearFailure: true),
    );
    final result = await _list(const ListInvoicesCommand());
    if (isClosed || generation != _requestGeneration) return;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(
            status: InvoicesListStatus.loaded,
            invoices: value.invoices,
            page: value.page,
            hasMore: value.hasMore,
            loadingMore: false,
            loadMoreFailed: false,
            fallbackSupervisionUnavailable:
                value.fallbackSupervisionUnavailable,
            fallbackSupervisionOverflow: value.fallbackSupervisionOverflow,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(status: InvoicesListStatus.error, failure: failure),
        );
    }
  }
}
