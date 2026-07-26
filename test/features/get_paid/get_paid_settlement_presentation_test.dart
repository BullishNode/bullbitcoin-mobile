import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_detail_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GetPaidTransaction _tx({
  GetPaidSettlement? settlement,
  GetPaidTransactionSource source = GetPaidTransactionSource.lightningAddress,
  String? invoiceId,
  GetPaidSettlementState settlementState = GetPaidSettlementState.settled,
}) => GetPaidTransaction(
  transactionId: '10000000-0000-4000-8000-000000000001',
  source: source,
  invoiceId: invoiceId,
  amountSat: 2100,
  receivedAt: DateTime.utc(2026, 7, 18, 12),
  rail: GetPaidTransactionRail.lightning,
  settlementState: settlementState,
  late: false,
  comment: null,
  settlement: settlement,
);

GetPaidSettlement _fiat({
  int? amountMinor = 12345,
  int? quotedAmountMinor,
  int? fiatPercentage,
  GetPaidSettlementLegStatus status = GetPaidSettlementLegStatus.settled,
}) => GetPaidSettlement(
  kind: GetPaidSettlementKind.fiat,
  fiatPercentage: fiatPercentage,
  fiat: [
    GetPaidFiatSettlementLeg(
      amountMinor: amountMinor,
      quotedAmountMinor: quotedAmountMinor,
      currency: 'CAD',
      orderId: '40000000-0000-4000-8000-000000000009',
      status: status,
    ),
  ],
);

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.themeData(AppThemeType.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: home,
);

Future<void> _pumpDetail(
  WidgetTester tester,
  GetPaidTransaction transaction,
) async {
  await tester.pumpWidget(
    _app(GetPaidTransactionDetailScreen(transaction: transaction)),
  );
  await tester.pump();
}

void main() {
  group('detail settlement section', () {
    testWidgets('every field renders as a row of the single details table', (
      tester,
    ) async {
      await _pumpDetail(tester, _tx(settlement: _fiat()));

      // One table holds everything — no second card, no loose boxed order-id
      // field below it.
      expect(find.byType(DetailsTable), findsOneWidget);
      expect(find.byType(CopyInput), findsNothing);
      // Base rows and the fiat leg rows live in the same table.
      expect(find.text('Bull Bitcoin order ID'), findsOneWidget);
      expect(find.text('40000000-0000-4000-8000-000000000009'), findsOneWidget);
    });

    testWidgets('renders a settled fiat leg with amount, status and order id', (
      tester,
    ) async {
      await _pumpDetail(tester, _tx(settlement: _fiat()));
      expect(find.text('123.45 CAD'), findsOneWidget);
      expect(find.text('Settled'), findsWidgets);
      expect(find.text('40000000-0000-4000-8000-000000000009'), findsOneWidget);
    });

    testWidgets(
      'renders a mixed settlement per-leg with L-BTC and Fiat amount + status '
      'rows, and keeps the payment-lifecycle Status row',
      (tester) async {
        await _pumpDetail(
          tester,
          _tx(
            settlement: GetPaidSettlement(
              kind: GetPaidSettlementKind.mixed,
              bitcoin: const [
                GetPaidBitcoinSettlementLeg(
                  amountSat: 60000,
                  status: GetPaidSettlementLegStatus.problem,
                ),
              ],
              fiat: _fiat().fiat,
            ),
          ),
        );
        // Per-leg labels of the one details table, in order.
        expect(find.text('L-BTC amount'), findsOneWidget);
        expect(find.text('L-BTC settlement status'), findsOneWidget);
        expect(find.text('Fiat amount'), findsOneWidget);
        expect(find.text('Fiat settlement status'), findsOneWidget);
        // Leg amounts.
        expect(find.text('60,000 sats'), findsOneWidget);
        expect(find.text('123.45 CAD'), findsOneWidget);
        // The bitcoin (L-BTC) leg's `problem` reuses the needs-attention
        // wording; the fiat leg is settled.
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('Settled'), findsWidgets);
        // The top payment-lifecycle Status row stays (distinct semantic from
        // the per-leg statuses).
        expect(find.text('Status'), findsOneWidget);
        // The Asset row is dropped entirely.
        expect(find.text('Asset'), findsNothing);
        expect(find.text('L-BTC'), findsNothing);
        expect(find.text('BTC'), findsNothing);
      },
    );

    testWidgets('a pending fiat leg shows the currency only, no amount', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          settlement: _fiat(
            amountMinor: null,
            status: GetPaidSettlementLegStatus.pending,
          ),
        ),
      );
      // The amount row names the expected currency only (v1 has no fiat amount
      // before settlement).
      expect(find.text('Fiat amount'), findsOneWidget);
      expect(find.text('CAD'), findsOneWidget);
      expect(find.textContaining('123.45'), findsNothing);
      // Pending status under the relabelled fiat status row.
      expect(find.text('Fiat settlement status'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders distinct copy per override reason', (tester) async {
      Future<void> pumpOverride(GetPaidFiatOverrideReason reason) =>
          _pumpDetail(
            tester,
            _tx(
              settlement: GetPaidSettlement(
                kind: GetPaidSettlementKind.bitcoin,
                overrideReason: reason,
              ),
            ),
          );

      await pumpOverride(GetPaidFiatOverrideReason.belowMinimum);
      expect(find.textContaining('below Bull Bitcoin'), findsOneWidget);

      await pumpOverride(GetPaidFiatOverrideReason.invalidSplit);
      expect(
        find.textContaining('fiat split could not be applied'),
        findsOneWidget,
      );

      await pumpOverride(GetPaidFiatOverrideReason.conversionUnavailable);
      expect(
        find.textContaining('fiat conversion was unavailable'),
        findsOneWidget,
      );

      await pumpOverride(GetPaidFiatOverrideReason.unknown);
      expect(find.textContaining('could not be applied'), findsOneWidget);
    });

    testWidgets('renders an unavailable settlement note', (tester) async {
      await _pumpDetail(
        tester,
        _tx(
          settlement: const GetPaidSettlement(
            kind: GetPaidSettlementKind.unavailable,
          ),
        ),
      );
      expect(find.text('Settlement details unavailable'), findsOneWidget);
    });

    testWidgets('plain bitcoin with no override shows no settlement rows', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          settlement: const GetPaidSettlement(
            kind: GetPaidSettlementKind.bitcoin,
          ),
        ),
      );
      // The "Fiat conversion" row is only rendered when there is something to
      // explain.
      expect(find.text('Fiat conversion'), findsNothing);
    });
  });

  group('batch 2 — quote, split, invoice id', () {
    testWidgets('a pending leg with a quote shows the quoted amount + label', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          settlementState: GetPaidSettlementState.pending,
          settlement: _fiat(
            amountMinor: null,
            quotedAmountMinor: 5000,
            status: GetPaidSettlementLegStatus.pending,
          ),
        ),
      );
      // The label marks it as a (repriceable) quote, not the plain amount.
      expect(find.text('Fiat amount (quoted)'), findsOneWidget);
      expect(find.text('Fiat amount'), findsNothing);
      expect(find.text('50.00 CAD'), findsOneWidget);
      // The awaiting-settlement explainer still fires for the pending leg.
      expect(find.textContaining('Awaiting settlement'), findsOneWidget);
    });

    testWidgets('a settled leg shows the credited amount, never the quote', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(settlement: _fiat(amountMinor: 12345, quotedAmountMinor: 12000)),
      );
      // Credited amount under the plain label; the (differing) quote is gone.
      expect(find.text('Fiat amount'), findsOneWidget);
      expect(find.text('Fiat amount (quoted)'), findsNothing);
      expect(find.text('123.45 CAD'), findsOneWidget);
      expect(find.textContaining('120.00'), findsNothing);
    });

    testWidgets('a mixed settlement shows the captured split row', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          settlement: GetPaidSettlement(
            kind: GetPaidSettlementKind.mixed,
            fiatPercentage: 40,
            bitcoin: const [
              GetPaidBitcoinSettlementLeg(
                amountSat: 60000,
                status: GetPaidSettlementLegStatus.settled,
              ),
            ],
            fiat: _fiat().fiat,
          ),
        ),
      );
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('60% Bitcoin · 40% fiat'), findsOneWidget);
    });

    testWidgets('a 100% fiat settlement shows the fiat-only split row', (
      tester,
    ) async {
      await _pumpDetail(tester, _tx(settlement: _fiat(fiatPercentage: 100)));
      expect(find.text('Split'), findsOneWidget);
      expect(find.text('100% fiat'), findsOneWidget);
    });

    testWidgets('a legacy row (null percentage) shows no split row', (
      tester,
    ) async {
      await _pumpDetail(tester, _tx(settlement: _fiat()));
      expect(find.text('Split'), findsNothing);
    });

    testWidgets('an invoice-sourced payment shows a copyable Invoice ID row', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          source: GetPaidTransactionSource.invoice,
          invoiceId: '50000000-0000-4000-8000-000000000005',
        ),
      );
      expect(find.text('Invoice ID'), findsOneWidget);
      expect(find.text('50000000-0000-4000-8000-000000000005'), findsOneWidget);
      // The row carries the copy affordance (same idiom as the order-id row).
      expect(find.byIcon(Icons.copy_outlined), findsWidgets);
    });

    testWidgets('a Lightning Address payment shows no Invoice ID row', (
      tester,
    ) async {
      await _pumpDetail(tester, _tx());
      expect(find.text('Invoice ID'), findsNothing);
    });
  });

  group('batch 5 — accounting rate row + sub-lines (R1 / R2)', () {
    // The real face≠leg case: invoice face USD, fiat leg CAD.
    GetPaidTransaction mixedFaceUsdLegCad({
      int? creationRateMinorPerBtc = 6416000,
      String? creationRateCurrency = 'USD',
      int? executionRateMinorPerBtc = 6390000,
    }) => _tx(
      settlementState: GetPaidSettlementState.settled,
      settlement: GetPaidSettlement(
        kind: GetPaidSettlementKind.mixed,
        fiatPercentage: 40,
        creationRateMinorPerBtc: creationRateMinorPerBtc,
        creationRateCurrency: creationRateCurrency,
        bitcoin: const [
          GetPaidBitcoinSettlementLeg(
            amountSat: 60000,
            status: GetPaidSettlementLegStatus.settled,
          ),
        ],
        fiat: [
          GetPaidFiatSettlementLeg(
            amountMinor: 12345,
            quotedAmountMinor: 12345,
            executionRateMinorPerBtc: executionRateMinorPerBtc,
            currency: 'CAD',
            orderId: '40000000-0000-4000-8000-000000000009',
            status: GetPaidSettlementLegStatus.settled,
          ),
        ],
      ),
    );

    testWidgets(
      'mixed settled shows the rate row and both sub-lines with the right '
      'currencies (face USD, leg CAD, never mixed)',
      (tester) async {
        await _pumpDetail(tester, mixedFaceUsdLegCad());
        // R1 rate-at-creation row, in the FACE currency (USD), marked ≈.
        expect(find.text('Rate at creation'), findsOneWidget);
        expect(find.text('≈ 64160.00 USD / BTC'), findsOneWidget);
        // The L-BTC ≈ sub-line: 60000 sats × 6416000 / 1e8 = 3850 minor → 38.50,
        // in the FACE currency (USD), marked ≈.
        expect(find.text('≈ 38.50 USD at creation rate'), findsOneWidget);
        // The R2 execution sub-line under the settled fiat amount, in the LEG
        // currency (CAD), exact (no ≈).
        expect(find.text('executed at 63900.00 CAD / BTC'), findsOneWidget);
        // The exact credited fiat amount stays in its own leg currency.
        expect(find.text('123.45 CAD'), findsOneWidget);
      },
    );

    testWidgets('sat-priced (no R1) shows NO rate-at-creation row', (
      tester,
    ) async {
      // A sat-priced invoice carries no creation rate; the row must never show.
      await _pumpDetail(
        tester,
        mixedFaceUsdLegCad(
          creationRateMinorPerBtc: null,
          creationRateCurrency: null,
        ),
      );
      expect(find.text('Rate at creation'), findsNothing);
      expect(find.textContaining('at creation rate'), findsNothing);
      // The R2 execution sub-line still shows (it is independent of R1).
      expect(find.text('executed at 63900.00 CAD / BTC'), findsOneWidget);
    });

    testWidgets('R1 rate without a face currency omits the row (no guess)', (
      tester,
    ) async {
      await _pumpDetail(tester, mixedFaceUsdLegCad(creationRateCurrency: null));
      // No currency context ⇒ neither the rate row nor the ≈ value sub-line.
      expect(find.text('Rate at creation'), findsNothing);
      expect(find.textContaining('at creation rate'), findsNothing);
    });

    testWidgets(
      'a pending leg shows the awaiting sub-line, never an execution rate',
      (tester) async {
        await _pumpDetail(
          tester,
          _tx(
            settlementState: GetPaidSettlementState.pending,
            settlement: GetPaidSettlement(
              kind: GetPaidSettlementKind.fiat,
              fiatPercentage: 100,
              creationRateMinorPerBtc: 6400000,
              creationRateCurrency: 'CAD',
              fiat: const [
                GetPaidFiatSettlementLeg(
                  amountMinor: null,
                  quotedAmountMinor: 5000,
                  // A pending leg never carries R2, even if the payload had one.
                  executionRateMinorPerBtc: null,
                  currency: 'CAD',
                  orderId: '40000000-0000-4000-8000-000000000009',
                  status: GetPaidSettlementLegStatus.pending,
                ),
              ],
            ),
          ),
        );
        expect(find.text('Rate at creation'), findsOneWidget);
        expect(find.textContaining('Awaiting settlement'), findsOneWidget);
        expect(find.textContaining('executed at'), findsNothing);
      },
    );

    testWidgets(
      'an old-server settlement renders zero new accounting elements',
      (tester) async {
        // Legacy fiat row: no R1, no R2 — batch-4 behaviour, bit-for-bit.
        await _pumpDetail(tester, _tx(settlement: _fiat(fiatPercentage: 100)));
        expect(find.text('Rate at creation'), findsNothing);
        expect(find.textContaining('at creation rate'), findsNothing);
        expect(find.textContaining('executed at'), findsNothing);
      },
    );
  });
}
