import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/widgets/inputs/copy_input.dart';
import 'package:bb_mobile/core/widgets/tables/details_table.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_detail_screen.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GetPaidTransaction _tx({GetPaidSettlement? settlement}) => GetPaidTransaction(
  transactionId: '10000000-0000-4000-8000-000000000001',
  source: GetPaidTransactionSource.lightningAddress,
  invoiceId: null,
  amountSat: 2100,
  receivedAt: DateTime.utc(2026, 7, 18, 12),
  rail: GetPaidTransactionRail.lightning,
  settlementState: GetPaidSettlementState.settled,
  late: false,
  comment: null,
  settlement: settlement,
);

GetPaidSettlement _fiat({
  int? amountMinor = 12345,
  GetPaidSettlementLegStatus status = GetPaidSettlementLegStatus.settled,
}) => GetPaidSettlement(
  kind: GetPaidSettlementKind.fiat,
  fiat: [
    GetPaidFiatSettlementLeg(
      amountMinor: amountMinor,
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

    testWidgets('renders a mixed settlement with a bitcoin portion', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _tx(
          settlement: GetPaidSettlement(
            kind: GetPaidSettlementKind.mixed,
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
      expect(find.text('60,000 sats'), findsOneWidget);
      expect(find.text('123.45 CAD'), findsOneWidget);
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
}
