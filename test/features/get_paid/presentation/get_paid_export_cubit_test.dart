import 'dart:async';

import 'package:bb_mobile/core/export/domain/transaction_export_saver.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/export_get_paid_transactions_csv_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockExportUsecase extends Mock
    implements ExportGetPaidTransactionsCsvUsecase {}

class _MockSaver extends Mock implements TransactionExportSaver {}

void main() {
  late _MockExportUsecase exportUsecase;
  late _MockSaver saver;

  setUp(() {
    exportUsecase = _MockExportUsecase();
    saver = _MockSaver();
  });

  test('leaving the route during the history walk emits nothing and never '
      'throws', () async {
    // The history walk is still in flight when the route (and cubit) is closed.
    final walk = Completer<Result<GetPaidCsvExport, GetPaidFailure>>();
    when(() => exportUsecase.execute()).thenAnswer((_) => walk.future);

    final cubit = GetPaidExportCubit(exportCsv: exportUsecase, saver: saver);
    final states = <GetPaidExportStatus>[];
    final sub = cubit.stream.listen((s) => states.add(s.status));

    final future = cubit.exportCsv();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    // The walk finishes only after disposal.
    walk.complete(
      Ok(const GetPaidCsvExport(csv: 'header\n', transactionCount: 1)),
    );

    await expectLater(future, completes); // no emit-after-close StateError
    expect(states, [GetPaidExportStatus.loading]);
    verifyNever(() => saver.save(any())); // never reached the save step
    await sub.cancel();
  });

  test(
    'leaving the route during the save emits nothing and never throws',
    () async {
      when(() => exportUsecase.execute()).thenAnswer(
        (_) async =>
            Ok(const GetPaidCsvExport(csv: 'header\n', transactionCount: 3)),
      );
      final save = Completer<bool>();
      when(() => saver.save(any())).thenAnswer((_) => save.future);

      final cubit = GetPaidExportCubit(exportCsv: exportUsecase, saver: saver);
      final states = <GetPaidExportStatus>[];
      final sub = cubit.stream.listen((s) => states.add(s.status));

      final future = cubit.exportCsv();
      await Future<void>.delayed(Duration.zero); // reach the save() await
      await cubit.close();
      save.complete(true); // save resolves only after disposal

      await expectLater(future, completes); // no emit-after-close StateError
      expect(states, [GetPaidExportStatus.loading]);
      await sub.cancel();
    },
  );
}
