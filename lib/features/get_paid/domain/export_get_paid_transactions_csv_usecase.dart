import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_csv_export_formatter.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/list_get_paid_transactions_usecase.dart';
import 'package:meta/meta.dart';

/// The result of a full-history export: the rendered CSV and how many receipts
/// it covers (0 lets the caller offer a "nothing to export" path instead of a
/// header-only file, mirroring the wallet exporter).
class GetPaidCsvExport {
  final String csv;
  final int transactionCount;

  const GetPaidCsvExport({required this.csv, required this.transactionCount});
}

/// Builds the merchant Get Paid accounting CSV over the FULL history. Pages the
/// server via the same cursor the history screen uses (empty cursor to start;
/// null `nextCursor` ends the walk), then hands the accumulated receipts to the
/// local [GetPaidCsvExportFormatter]. No server export endpoint is involved.
class ExportGetPaidTransactionsCsvUsecase {
  /// The page size used while walking the history. The plan calls for paging in
  /// hundreds; the server caps a page at
  /// [bullnymGetPaidTransactionMaxPageSize].
  static const int pageSize = 100;

  /// Defence against a server that never returns a null cursor: cap the walk so
  /// the export can never loop forever. 1000 pages × 100 = 100k receipts.
  static const int maxPages = 1000;

  final ListGetPaidTransactionsUsecase _listTransactions;
  final GetPaidCsvExportFormatter _formatter;

  const ExportGetPaidTransactionsCsvUsecase({
    required ListGetPaidTransactionsUsecase listTransactions,
    GetPaidCsvExportFormatter formatter = const GetPaidCsvExportFormatter(),
  }) : _listTransactions = listTransactions,
       _formatter = formatter;

  @useResult
  Future<Result<GetPaidCsvExport, GetPaidFailure>> execute() async {
    final transactions = <GetPaidTransaction>[];
    final seenKeys = <String>{};
    var cursor = '';
    for (var page = 0; page < maxPages; page++) {
      final result = await _listTransactions.execute(
        cursor: cursor,
        limit: pageSize,
      );
      switch (result) {
        case Ok(:final value):
          for (final transaction in value.transactions) {
            // Dedup defensively across page boundaries (same rule the history
            // list uses) so a repeated row never double-counts in the export.
            if (seenKeys.add(transaction.stableKey)) {
              transactions.add(transaction);
            }
          }
          final next = value.nextCursor;
          if (next == null) {
            return Ok(_export(transactions));
          }
          cursor = next;
        case Err(:final failure):
          return Err(failure);
      }
    }
    // Reached the page cap without the server ending the walk: return what we
    // have rather than spin forever.
    return Ok(_export(transactions));
  }

  GetPaidCsvExport _export(List<GetPaidTransaction> transactions) =>
      GetPaidCsvExport(
        csv: _formatter.format(transactions),
        transactionCount: transactions.length,
      );
}
