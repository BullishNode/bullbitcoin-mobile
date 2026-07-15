import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_comment_history_state.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';

LightningAddressPaymentComment _comment({
  required String id,
  required int receivedAtUnix,
  String text = 'Thank you',
}) {
  return LightningAddressPaymentComment(
    intentId: id,
    nym: 'merchant',
    amountMsat: 42000,
    comment: text,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(
      receivedAtUnix * 1000,
      isUtc: true,
    ),
  );
}

LightningAddressFacade _facade(
  Future<LightningAddressPaymentCommentPage> Function({
    required int page,
    required int pageSize,
  })
  list,
) {
  return LightningAddressFacade(
    prepareWallet: () => throw UnimplementedError(),
    lookupRegistration: ({required npubHex}) => throw UnimplementedError(),
    registerWalletOwned: ({required nym}) => throw UnimplementedError(),
    lookupWalletOwnedRegistration: () => throw UnimplementedError(),
    ensureRegistrationLive: () => throw UnimplementedError(),
    listPaymentComments: list,
  );
}

void main() {
  test(
    'pages authenticated history, deduplicates a shifted boundary',
    () async {
      final calls = <int>[];
      final newest = _comment(
        id: '5de539d7-b0f2-4d4a-a308-d0f31dc111b6',
        receivedAtUnix: 200,
      );
      final boundary = _comment(
        id: '4de539d7-b0f2-4d4a-a308-d0f31dc111b5',
        receivedAtUnix: 100,
      );
      final older = _comment(
        id: '3de539d7-b0f2-4d4a-a308-d0f31dc111b4',
        receivedAtUnix: 50,
      );
      final cubit = GetPaidCommentHistoryCubit(
        _facade(({required page, required pageSize}) async {
          calls.add(page);
          return LightningAddressPaymentCommentPage(
            comments: page == 1 ? [newest, boundary] : [boundary, older],
            page: page,
            pageSize: pageSize,
            hasMore: page == 1,
          );
        }),
      );
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      expect(calls, [1, 2]);
      expect(cubit.state.status, GetPaidCommentHistoryStatus.loaded);
      expect(cubit.state.comments.map((comment) => comment.intentId), [
        newest.intentId,
        boundary.intentId,
        older.intentId,
      ]);
      expect(cubit.state.hasMore, isFalse);
      expect(cubit.state.nextPage, 3);
    },
  );

  test(
    'keeps loaded rows private and retryable when a later page fails',
    () async {
      final first = _comment(
        id: '4de539d7-b0f2-4d4a-a308-d0f31dc111b5',
        receivedAtUnix: 100,
      );
      final cubit = GetPaidCommentHistoryCubit(
        _facade(({required page, required pageSize}) async {
          if (page > 1) {
            throw const LightningAddressException.unexpected();
          }
          return LightningAddressPaymentCommentPage(
            comments: [first],
            page: page,
            pageSize: pageSize,
            hasMore: true,
          );
        }),
      );
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.loadMore();

      expect(cubit.state.comments, [first]);
      expect(cubit.state.loadMoreFailed, isTrue);
      expect(cubit.state.isLoadingMore, isFalse);
    },
  );
}
