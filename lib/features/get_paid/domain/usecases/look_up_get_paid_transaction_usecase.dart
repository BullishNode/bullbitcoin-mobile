import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/list_get_paid_transactions_usecase.dart';
import 'package:meta/meta.dart';

/// Reloads one receipt from the authenticated Get Paid history.
///
/// Bullnym exposes the receipt collection as a cursor-paged resource rather than
/// a separate detail endpoint. The receipt's `(source, transaction_id)` pair is
/// its stable identity, so this use case walks the collection until that exact
/// row is found. Presentation never guesses that the first page still contains
/// an older receipt.
class LookUpGetPaidTransactionUsecase {
  static const int pageSize = 100;
  static const int maxPages = 1000;

  final ListGetPaidTransactionsUsecase _listTransactions;

  const LookUpGetPaidTransactionUsecase(this._listTransactions);

  @useResult
  Future<Result<GetPaidTransaction, GetPaidFailure>> execute({
    required GetPaidTransactionSource source,
    required String transactionId,
  }) async {
    final stableKey = '${source.name}:$transactionId';
    final requestedCursors = <String>{''};
    var cursor = '';

    for (var page = 0; page < maxPages; page++) {
      final result = await _listTransactions.execute(
        cursor: cursor,
        limit: pageSize,
      );
      switch (result) {
        case Ok(:final value):
          for (final transaction in value.transactions) {
            if (transaction.stableKey == stableKey) return Ok(transaction);
          }

          final next = value.nextCursor;
          if (next == null) {
            return const Err(
              GetPaidFailure.unavailable(
                logMessage:
                    'receipt detail refresh could not find the original row',
              ),
            );
          }
          if (!requestedCursors.add(next)) {
            return const Err(
              GetPaidFailure.incompleteHistory(
                logMessage:
                    'receipt detail refresh encountered a repeated cursor',
              ),
            );
          }
          cursor = next;
        case Err(:final failure):
          return Err(failure);
      }
    }

    return const Err(
      GetPaidFailure.incompleteHistory(
        logMessage: 'receipt detail refresh exceeded the history page cap',
      ),
    );
  }
}
