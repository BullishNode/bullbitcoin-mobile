import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';

enum GetPaidCommentHistoryStatus { initial, loading, loaded, failure }

class GetPaidCommentHistoryState {
  final GetPaidCommentHistoryStatus status;
  final List<LightningAddressPaymentComment> comments;
  final int nextPage;
  final bool hasMore;
  final bool isLoadingMore;
  final bool loadMoreFailed;

  const GetPaidCommentHistoryState({
    this.status = GetPaidCommentHistoryStatus.initial,
    this.comments = const [],
    this.nextPage = 1,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  bool get isEmpty =>
      status == GetPaidCommentHistoryStatus.loaded && comments.isEmpty;

  GetPaidCommentHistoryState copyWith({
    GetPaidCommentHistoryStatus? status,
    List<LightningAddressPaymentComment>? comments,
    int? nextPage,
    bool? hasMore,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) {
    return GetPaidCommentHistoryState(
      status: status ?? this.status,
      comments: comments ?? this.comments,
      nextPage: nextPage ?? this.nextPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
    );
  }
}
