import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_transaction_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLookUpTransaction extends Mock
    implements LookUpGetPaidTransactionUsecase {}

GetPaidTransaction _transaction(GetPaidSettlementState state) {
  return GetPaidTransaction(
    transactionId: '10000000-0000-4000-8000-000000000001',
    source: GetPaidTransactionSource.lightningAddress,
    invoiceId: null,
    amountSat: 1000,
    receivedAt: DateTime.utc(2026),
    rail: GetPaidTransactionRail.lightning,
    settlementState: state,
    late: false,
    comment: null,
  );
}

void main() {
  test(
    'refresh replaces a pending receipt with the settled projection',
    () async {
      final pending = _transaction(GetPaidSettlementState.pending);
      final settled = _transaction(GetPaidSettlementState.settled);
      final lookup = _MockLookUpTransaction();
      when(
        () => lookup.execute(
          source: pending.source,
          transactionId: pending.transactionId,
        ),
      ).thenAnswer((_) async => Ok(settled));
      final cubit = GetPaidTransactionDetailCubit(
        lookup,
        initialTransaction: pending,
      );

      await cubit.refresh();

      expect(cubit.state.transaction, same(settled));
      expect(cubit.state.refreshFailed, isFalse);
      await cubit.close();
    },
  );

  test(
    'refresh failure retains the last verified receipt and marks it stale',
    () async {
      final transaction = _transaction(GetPaidSettlementState.settled);
      final lookup = _MockLookUpTransaction();
      when(
        () => lookup.execute(
          source: transaction.source,
          transactionId: transaction.transactionId,
        ),
      ).thenAnswer((_) async => const Err(GetPaidFailure.unavailable()));
      final cubit = GetPaidTransactionDetailCubit(
        lookup,
        initialTransaction: transaction,
      );

      await cubit.refresh();

      expect(cubit.state.transaction, same(transaction));
      expect(cubit.state.isRefreshing, isFalse);
      expect(cubit.state.refreshFailed, isTrue);
      await cubit.close();
    },
  );
}
