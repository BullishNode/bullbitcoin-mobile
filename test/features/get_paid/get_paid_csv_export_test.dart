import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/get_paid/domain/export_get_paid_transactions_csv_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_csv_export_formatter.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/list_get_paid_transactions_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockListTransactions extends Mock
    implements ListGetPaidTransactionsUsecase {}

const _fiatOrderId = '40000000-0000-4000-8000-000000000009';
const _invoiceId = '50000000-0000-4000-8000-000000000005';

GetPaidTransaction _tx({
  String id = '10000000-0000-4000-8000-000000000001',
  int amountSat = 100000,
  GetPaidTransactionSource source = GetPaidTransactionSource.invoice,
  String? comment,
  GetPaidSettlement? settlement,
}) => GetPaidTransaction(
  transactionId: id,
  source: source,
  invoiceId: source == GetPaidTransactionSource.lightningAddress
      ? null
      : _invoiceId,
  amountSat: amountSat,
  receivedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
  rail: GetPaidTransactionRail.lightning,
  settlementState: GetPaidSettlementState.settled,
  late: false,
  comment: comment,
  settlement: settlement,
);

// Mixed, FACE currency USD (R1), fiat LEG currency CAD (R2) — the real
// face≠leg case.
GetPaidSettlement _mixedFaceUsdLegCad({
  int? creationRateMinorPerBtc = 6416000,
  String? creationRateCurrency = 'USD',
}) => GetPaidSettlement(
  kind: GetPaidSettlementKind.mixed,
  fiatPercentage: 40,
  creationRateMinorPerBtc: creationRateMinorPerBtc,
  creationRateCurrency: creationRateCurrency,
  bitcoin: const [
    GetPaidBitcoinSettlementLeg(
      amountSat: 60000,
      network: 'liquid',
      status: GetPaidSettlementLegStatus.settled,
    ),
  ],
  fiat: const [
    GetPaidFiatSettlementLeg(
      amountMinor: 12345,
      quotedAmountMinor: 12345,
      executionRateMinorPerBtc: 6390000,
      currency: 'CAD',
      orderId: _fiatOrderId,
      status: GetPaidSettlementLegStatus.settled,
    ),
  ],
);

void main() {
  const formatter = GetPaidCsvExportFormatter();

  group('GetPaidCsvExportFormatter', () {
    test('header lists every accounting column in order', () {
      final csv = formatter.format([]);
      expect(
        csv.trim(),
        'received_at,source,invoice_id,order_id,face_amount,face_currency,'
        'total_sats,creation_rate_face_ccy,split_pct,btc_leg_sats,'
        'btc_leg_value_est_face_ccy,fiat_credited,fiat_credited_currency,'
        'execution_rate_leg_ccy,btc_leg_status,fiat_leg_status,settlement_kind,'
        'payment_status,comment_present',
      );
    });

    test('a mixed row renders exact columns, face≠leg currencies kept apart', () {
      final csv = formatter.format([_tx(settlement: _mixedFaceUsdLegCad())]);
      final dataRow = csv.trim().split('\n')[1];
      // The btc-leg estimate: 60000 sats × 6416000 / 1e8 = 3850 minor → 38.50,
      // in the FACE currency (USD); R2 (63900.00) is in the LEG currency (CAD).
      expect(
        dataRow,
        '2026-01-02T03:04:05.000Z,invoice,$_invoiceId,$_fiatOrderId,,USD,'
        '100000,64160.00,40,60000,38.50,123.45,CAD,63900.00,settled,settled,'
        'mixed,settled,false',
      );
    });

    test('the _est column is empty when R1 is absent', () {
      final csv = formatter.format([
        _tx(
          settlement: _mixedFaceUsdLegCad(
            creationRateMinorPerBtc: null,
            creationRateCurrency: null,
          ),
        ),
      ]);
      final fields = csv.trim().split('\n')[1].split(',');
      // creation_rate_face_ccy (idx 7), face_currency (idx 5) and
      // btc_leg_value_est_face_ccy (idx 10) are all empty; btc_leg_sats stays.
      expect(fields[5], '');
      expect(fields[7], '');
      expect(fields[10], '');
      expect(fields[9], '60000');
    });

    test('the private comment text is never exported, only its presence', () {
      final csv = formatter.format([
        _tx(comment: 'secret memo', settlement: _mixedFaceUsdLegCad()),
      ]);
      expect(csv.contains('secret memo'), isFalse);
      expect(csv.trim().split('\n')[1].split(',').last, 'true');
    });
  });

  group('ExportGetPaidTransactionsCsvUsecase paging', () {
    late _MockListTransactions list;

    setUp(() {
      list = _MockListTransactions();
    });

    test('walks every page via the cursor and covers all receipts', () async {
      when(() => list.execute(cursor: '', limit: 100)).thenAnswer(
        (_) async => Ok(
          GetPaidTransactionPage(
            transactions: [_tx(id: '10000000-0000-4000-8000-000000000001')],
            nextCursor: 'page-2',
          ),
        ),
      );
      when(() => list.execute(cursor: 'page-2', limit: 100)).thenAnswer(
        (_) async => Ok(
          GetPaidTransactionPage(
            transactions: [_tx(id: '20000000-0000-4000-8000-000000000002')],
            nextCursor: null,
          ),
        ),
      );

      final usecase = ExportGetPaidTransactionsCsvUsecase(
        listTransactions: list,
      );
      final result = await usecase.execute();

      final export = switch (result) {
        Ok(:final value) => value,
        Err() => fail('expected the export to succeed'),
      };
      expect(export.transactionCount, 2);
      // Header + 2 data rows.
      expect(export.csv.trim().split('\n').length, 3);
      verify(() => list.execute(cursor: '', limit: 100)).called(1);
      verify(() => list.execute(cursor: 'page-2', limit: 100)).called(1);
    });

    test('a page failure aborts the export', () async {
      when(
        () => list.execute(cursor: '', limit: 100),
      ).thenAnswer((_) async => const Err(GetPaidFailure.unavailable()));

      final usecase = ExportGetPaidTransactionsCsvUsecase(
        listTransactions: list,
      );
      final result = await usecase.execute();
      expect(result, isA<Err<GetPaidCsvExport, GetPaidFailure>>());
    });

    test(
      'reaching the page cap with a cursor still pending fails as incomplete',
      () async {
        // The server never returns a null cursor: every page yields a fresh
        // cursor so the loop guard never trips, and the walk hits the cap.
        var page = 0;
        when(
          () => list.execute(
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => Ok(
            GetPaidTransactionPage(
              transactions: const [],
              nextCursor: 'page-${page++}',
            ),
          ),
        );

        final usecase = ExportGetPaidTransactionsCsvUsecase(
          listTransactions: list,
        );
        final result = await usecase.execute();

        final failure = switch (result) {
          Err(:final failure) => failure,
          Ok() => fail('expected the export to fail, not truncate silently'),
        };
        expect(failure, isA<GetPaidIncompleteHistoryFailure>());
        // Walked exactly the cap — never presented a partial file as complete.
        verify(
          () => list.execute(
            cursor: any(named: 'cursor'),
            limit: any(named: 'limit'),
          ),
        ).called(ExportGetPaidTransactionsCsvUsecase.maxPages);
      },
    );

    test('a repeated server cursor aborts the export as incomplete', () async {
      when(() => list.execute(cursor: '', limit: 100)).thenAnswer(
        (_) async => Ok(
          GetPaidTransactionPage(
            transactions: [_tx(id: '10000000-0000-4000-8000-000000000001')],
            nextCursor: 'loop',
          ),
        ),
      );
      // The server hands back 'loop' a second time: a cycle, not progress.
      when(() => list.execute(cursor: 'loop', limit: 100)).thenAnswer(
        (_) async => Ok(
          GetPaidTransactionPage(
            transactions: [_tx(id: '20000000-0000-4000-8000-000000000002')],
            nextCursor: 'loop',
          ),
        ),
      );

      final usecase = ExportGetPaidTransactionsCsvUsecase(
        listTransactions: list,
      );
      final result = await usecase.execute();

      final failure = switch (result) {
        Err(:final failure) => failure,
        Ok() => fail('expected the looping export to fail'),
      };
      expect(failure, isA<GetPaidIncompleteHistoryFailure>());
      verify(() => list.execute(cursor: '', limit: 100)).called(1);
      verify(() => list.execute(cursor: 'loop', limit: 100)).called(1);
    });
  });
}
