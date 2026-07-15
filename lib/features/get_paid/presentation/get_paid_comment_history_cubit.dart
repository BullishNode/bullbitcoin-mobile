import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class GetPaidCommentHistoryCubit extends Cubit<GetPaidCommentHistoryState> {
  static const pageSize = 20;

  final LightningAddressFacade _lightningAddress;
  int _generation = 0;

  GetPaidCommentHistoryCubit(this._lightningAddress)
    : super(const GetPaidCommentHistoryState());

  Future<void> load() => refresh();

  Future<void> refresh() async {
    final generation = ++_generation;
    emit(
      const GetPaidCommentHistoryState(
        status: GetPaidCommentHistoryStatus.loading,
      ),
    );
    try {
      final page = await _lightningAddress.listPaymentComments(
        page: 1,
        pageSize: pageSize,
      );
      if (_isStale(generation)) return;
      emit(
        GetPaidCommentHistoryState(
          status: GetPaidCommentHistoryStatus.loaded,
          comments: page.comments,
          nextPage: 2,
          hasMore:
              page.hasMore &&
              page.page < LightningAddressPaymentCommentPage.maxPage,
        ),
      );
    } on LightningAddressException {
      if (_isStale(generation)) return;
      emit(
        const GetPaidCommentHistoryState(
          status: GetPaidCommentHistoryStatus.failure,
        ),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.status != GetPaidCommentHistoryStatus.loaded ||
        !state.hasMore ||
        state.isLoadingMore) {
      return;
    }
    final generation = _generation;
    final requestedPage = state.nextPage;
    emit(state.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final page = await _lightningAddress.listPaymentComments(
        page: requestedPage,
        pageSize: pageSize,
      );
      if (_isStale(generation)) return;
      final byIntent = <String, LightningAddressPaymentComment>{
        for (final comment in state.comments) comment.intentId: comment,
        for (final comment in page.comments) comment.intentId: comment,
      };
      final comments = byIntent.values.toList()
        ..sort((left, right) {
          final timeOrder = right.receivedAt.compareTo(left.receivedAt);
          return timeOrder != 0
              ? timeOrder
              : right.intentId.compareTo(left.intentId);
        });
      emit(
        state.copyWith(
          comments: List.unmodifiable(comments),
          nextPage: requestedPage + 1,
          hasMore:
              page.hasMore &&
              page.page < LightningAddressPaymentCommentPage.maxPage,
          isLoadingMore: false,
          loadMoreFailed: false,
        ),
      );
    } on LightningAddressException {
      if (_isStale(generation)) return;
      emit(state.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }

  bool _isStale(int generation) => isClosed || generation != _generation;
}
