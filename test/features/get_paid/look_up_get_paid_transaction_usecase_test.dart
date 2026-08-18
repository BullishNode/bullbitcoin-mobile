import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/list_get_paid_transactions_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_transaction_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockListTransactions extends Mock
    implements ListGetPaidTransactionsUsecase {}

GetPaidTransaction _transaction({
  required String id,
  required GetPaidTransactionSource source,
  GetPaidSettlementState state = GetPaidSettlementState.pending,
}) {
  return GetPaidTransaction(
    transactionId: id,
    source: source,
    invoiceId: source == GetPaidTransactionSource.lightningAddress
        ? null
        : '50000000-0000-4000-8000-000000000005',
    amountSat: 1000,
    receivedAt: DateTime.utc(2026),
    rail: GetPaidTransactionRail.lightning,
    settlementState: state,
    late: false,
    comment: null,
  );
}

void main() {
  const targetId = '10000000-0000-4000-8000-000000000001';
  const otherId = '20000000-0000-4000-8000-000000000002';

  test('walks history and matches the stable source plus receipt id', () async {
    final list = _MockListTransactions();
    final target = _transaction(
      id: targetId,
      source: GetPaidTransactionSource.invoice,
      state: GetPaidSettlementState.settled,
    );
    when(() => list.execute(cursor: '', limit: 100)).thenAnswer(
      (_) async => Ok(
        GetPaidTransactionPage(
          transactions: [
            _transaction(
              id: targetId,
              source: GetPaidTransactionSource.lightningAddress,
            ),
            _transaction(id: otherId, source: GetPaidTransactionSource.invoice),
          ],
          nextCursor: 'older',
        ),
      ),
    );
    when(() => list.execute(cursor: 'older', limit: 100)).thenAnswer(
      (_) async =>
          Ok(GetPaidTransactionPage(transactions: [target], nextCursor: null)),
    );

    final result = await LookUpGetPaidTransactionUsecase(list).execute(
      source: GetPaidTransactionSource.invoice,
      transactionId: targetId,
    );

    expect(result, isA<Ok<GetPaidTransaction, GetPaidFailure>>());
    expect(
      (result as Ok<GetPaidTransaction, GetPaidFailure>).value,
      same(target),
    );
    verify(() => list.execute(cursor: 'older', limit: 100)).called(1);
  });

  test(
    'returns a failure when the original receipt is no longer listed',
    () async {
      final list = _MockListTransactions();
      when(() => list.execute(cursor: '', limit: 100)).thenAnswer(
        (_) async => Ok(
          GetPaidTransactionPage(transactions: const [], nextCursor: null),
        ),
      );

      final result = await LookUpGetPaidTransactionUsecase(list).execute(
        source: GetPaidTransactionSource.lightningAddress,
        transactionId: targetId,
      );

      expect(result, isA<Err<GetPaidTransaction, GetPaidFailure>>());
    },
  );
}
