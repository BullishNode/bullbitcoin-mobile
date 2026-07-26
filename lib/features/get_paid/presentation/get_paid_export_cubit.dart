import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/export_get_paid_transactions_csv_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_state.dart';
import 'package:bb_mobile/features/transactions/application/ports/transaction_export_saver.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drives the merchant Get Paid accounting CSV export: page the full history,
/// then hand the rendered CSV to the shared platform saver/share sheet (reusing
/// the wallet exporter's [TransactionExportSaver]). A cancelled save returns to
/// initial; a history with no receipts surfaces an empty state rather than
/// saving a header-only file.
class GetPaidExportCubit extends Cubit<GetPaidExportState> {
  final ExportGetPaidTransactionsCsvUsecase _exportCsv;
  final TransactionExportSaver _saver;

  GetPaidExportCubit({
    required ExportGetPaidTransactionsCsvUsecase exportCsv,
    required TransactionExportSaver saver,
    // Preserve public named parameters while keeping collaborators private.
    // ignore: prefer_initializing_formals
  }) : _exportCsv = exportCsv,
       // ignore: prefer_initializing_formals
       _saver = saver,
       super(const GetPaidExportState());

  Future<void> exportCsv() async {
    if (state.isLoading) return;
    emit(const GetPaidExportState(status: GetPaidExportStatus.loading));
    final result = await _exportCsv.execute();
    switch (result) {
      case Ok(:final value):
        if (value.transactionCount == 0) {
          emit(const GetPaidExportState(status: GetPaidExportStatus.empty));
          return;
        }
        try {
          final saved = await _saver.save(value.csv);
          emit(
            GetPaidExportState(
              status: saved
                  ? GetPaidExportStatus.success
                  : GetPaidExportStatus.initial,
            ),
          );
        } on Exception catch (error, trace) {
          log.warning(
            'Get Paid CSV export save failed',
            error: error,
            trace: trace,
          );
          emit(const GetPaidExportState(status: GetPaidExportStatus.failure));
        }
      case Err(:final failure):
        log.warning(
          'Get Paid CSV export failed',
          error: failure.logMessage ?? failure.runtimeType.toString(),
        );
        emit(const GetPaidExportState(status: GetPaidExportStatus.failure));
    }
  }
}
