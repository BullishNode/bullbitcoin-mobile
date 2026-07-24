import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_history_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_detail_screen.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_transaction_history_screen.dart';
import 'package:bb_mobile/features/invoices/public/invoices_routes.dart';
import 'package:bb_mobile/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bull_ui/bull_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _StubHistoryCubit extends Cubit<GetPaidTransactionHistoryState>
    implements GetPaidTransactionHistoryCubit {
  int loadCalls = 0;
  int refreshCalls = 0;
  int loadMoreCalls = 0;

  _StubHistoryCubit(super.initialState);

  @override
  Future<void> load() async => loadCalls++;

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> loadMore() async => loadMoreCalls++;
}

// CurrencyText on the list rows reads the bitcoin unit and hide-amounts flag
// from a SettingsCubit, so the rows need one in the tree.
class _MockSettingsCubit extends Mock implements SettingsCubit {}

SettingsCubit _settingsCubit() {
  final cubit = _MockSettingsCubit();
  when(() => cubit.state).thenReturn(
    const SettingsState(
      storedSettings: SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
        hideAmounts: false,
      ),
    ),
  );
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<SettingsState>.empty());
  return cubit;
}

GetPaidTransaction _transaction({
  GetPaidTransactionSource source = GetPaidTransactionSource.lightningAddress,
  String? comment,
  String transactionId = '10000000-0000-4000-8000-000000000001',
  DateTime? receivedAt,
  GetPaidTransactionRail rail = GetPaidTransactionRail.lightning,
  GetPaidSettlementState settlementState = GetPaidSettlementState.settled,
  GetPaidSettlement? settlement,
}) {
  return GetPaidTransaction(
    transactionId: transactionId,
    source: source,
    invoiceId: source == GetPaidTransactionSource.lightningAddress
        ? null
        : '50000000-0000-4000-8000-000000000005',
    amountSat: 2100,
    receivedAt: receivedAt ?? DateTime.utc(2026, 7, 18, 12),
    rail: rail,
    settlementState: settlementState,
    late: false,
    comment: comment,
    settlement: settlement,
  );
}

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.themeData(AppThemeType.light),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: BlocProvider<SettingsCubit>.value(value: _settingsCubit(), child: home),
);

Future<_StubHistoryCubit> _pumpHistory(
  WidgetTester tester,
  GetPaidTransactionHistoryState state,
) async {
  final cubit = _StubHistoryCubit(state);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    _app(
      BlocProvider<GetPaidTransactionHistoryCubit>.value(
        value: cubit,
        child: const GetPaidTransactionHistoryScreen(),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  testWidgets('renders first-load skeleton, empty, and retry states', (
    tester,
  ) async {
    await _pumpHistory(
      tester,
      const GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loading,
      ),
    );
    expect(find.byType(BullShimmerLine), findsWidgets);

    await _pumpHistory(
      tester,
      const GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loaded,
      ),
    );
    expect(find.text('No payments yet'), findsOneWidget);

    final failureCubit = await _pumpHistory(
      tester,
      const GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.failure,
        failure: GetPaidFailure.unavailable(),
      ),
    );
    await tester.tap(find.text('Retry'));
    expect(failureCubit.refreshCalls, 1);
  });

  testWidgets('list shows payment facts but keeps comment private to detail', (
    tester,
  ) async {
    final cubit = await _pumpHistory(
      tester,
      GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loaded,
        transactions: [_transaction(comment: 'private payer note')],
        nextCursor: 'next',
      ),
    );

    expect(find.text('2,100 sats'), findsOneWidget);
    // Source chip + network pill share the wallet-list grammar; the coarse
    // "Lightning · Settled" status line is gone (settled rows are quiet).
    expect(find.text('Lightning Address'), findsOneWidget);
    expect(find.textContaining('Lightning'), findsWidgets);
    expect(find.text('Settled'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.text('private payer note'), findsNothing);
    await tester.tap(find.text('Load more'));
    expect(cubit.loadMoreCalls, 1);
  });

  testWidgets(
    'list row shows amount, source chip, network pill and a needs-attention '
    'chip only when action is required',
    (tester) async {
      await _pumpHistory(
        tester,
        GetPaidTransactionHistoryState(
          status: GetPaidTransactionHistoryStatus.loaded,
          transactions: [
            _transaction(
              transactionId: '10000000-0000-4000-8000-000000000001',
              settlementState: GetPaidSettlementState.settled,
            ),
            _transaction(
              source: GetPaidTransactionSource.invoice,
              transactionId: '20000000-0000-4000-8000-000000000002',
              settlementState: GetPaidSettlementState.problem,
            ),
          ],
        ),
      );

      // Amount (CurrencyText) + network pill for both rows.
      expect(find.text('2,100 sats'), findsNWidgets(2));
      expect(find.text('Lightning'), findsNWidgets(2));
      // Source chips.
      expect(find.text('Lightning Address'), findsOneWidget);
      expect(find.text('Invoice'), findsOneWidget);
      // Needs-attention chip on the problem row only.
      expect(find.text('Needs attention'), findsOneWidget);
      // No chevron, no coarse settlement-kind line.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    },
  );

  testWidgets('row opens detail, where comment and invoice link are explicit', (
    tester,
  ) async {
    final transaction = _transaction(
      source: GetPaidTransactionSource.invoice,
      comment: 'private payer note',
    );
    final cubit = _StubHistoryCubit(
      GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loaded,
        transactions: [transaction],
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              BlocProvider<GetPaidTransactionHistoryCubit>.value(
                value: cubit,
                child: const GetPaidTransactionHistoryScreen(),
              ),
          routes: [
            GoRoute(
              name: GetPaidDashboardRoute.getPaidTransactionDetail.name,
              path: 'detail',
              builder: (context, state) => GetPaidTransactionDetailScreen(
                transaction: state.extra! as GetPaidTransaction,
              ),
            ),
          ],
        ),
        GoRoute(
          name: InvoicesRoute.detail.name,
          path: '/invoices/:id',
          builder: (context, state) =>
              Scaffold(body: Text('invoice-${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      BlocProvider<SettingsCubit>.value(
        value: _settingsCubit(),
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.themeData(AppThemeType.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('private payer note'), findsNothing);
    await tester.tap(
      find.byKey(ValueKey('get-paid-transaction-${transaction.stableKey}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('private payer note'), findsOneWidget);
    expect(find.text(transaction.transactionId), findsNothing);
    expect(find.text(transaction.invoiceId!), findsNothing);
    await tester.tap(find.text('View invoice'));
    await tester.pumpAndSettle();
    expect(find.text('invoice-${transaction.invoiceId}'), findsOneWidget);
    // The route carries only the invoice id (a UUID), never the private-link
    // fragment — nothing resembling a #v1. link string reaches the router.
    expect(find.textContaining('#v1.'), findsNothing);
  });

  group('settlement-kind pill precedence', () {
    testWidgets('a trustworthy server settlement kind wins', (tester) async {
      await _pumpHistory(
        tester,
        GetPaidTransactionHistoryState(
          status: GetPaidTransactionHistoryStatus.loaded,
          transactions: [
            _transaction(
              settlement: const GetPaidSettlement(
                kind: GetPaidSettlementKind.mixed,
              ),
            ),
          ],
        ),
      );

      expect(find.text('Mixed Fiat-BTC'), findsOneWidget);
    });

    testWidgets(
      'an unclassified row uses the expected product kind from config',
      (tester) async {
        await _pumpHistory(
          tester,
          GetPaidTransactionHistoryState(
            status: GetPaidTransactionHistoryStatus.loaded,
            transactions: [_transaction()],
            expectedSettlementKinds: const {
              FiatSettlementProduct.lightningAddress: FiatSettlementMode.mixed,
            },
          ),
        );

        // No server settlement classification, but the product config says this
        // Lightning Address product is supposed to settle mixed.
        expect(find.text('Mixed Fiat-BTC'), findsOneWidget);
      },
    );

    testWidgets(
      'no server kind and no expected-kind map falls back to the rail label',
      (tester) async {
        await _pumpHistory(
          tester,
          GetPaidTransactionHistoryState(
            status: GetPaidTransactionHistoryStatus.loaded,
            transactions: [_transaction(rail: GetPaidTransactionRail.liquid)],
          ),
        );

        // The facade was unavailable (no expected-kind map): never an invented
        // kind, just the original rail label.
        expect(find.text('Liquid'), findsOneWidget);
        expect(find.text('Mixed Fiat-BTC'), findsNothing);
      },
    );
  });

  testWidgets('groups transactions under wallet-history day headers', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    await _pumpHistory(
      tester,
      GetPaidTransactionHistoryState(
        status: GetPaidTransactionHistoryStatus.loaded,
        transactions: [
          _transaction(
            transactionId: '10000000-0000-4000-8000-000000000001',
            receivedAt: today.toUtc(),
          ),
          _transaction(
            transactionId: '20000000-0000-4000-8000-000000000002',
            receivedAt: yesterday.toUtc(),
          ),
        ],
      ),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets(
    'pending fiat detail names the expected currency and explains, with no '
    'invented amount',
    (tester) async {
      await tester.pumpWidget(
        _app(
          GetPaidTransactionDetailScreen(
            transaction: _transaction(
              source: GetPaidTransactionSource.invoice,
              settlementState: GetPaidSettlementState.pending,
              settlement: const GetPaidSettlement(
                kind: GetPaidSettlementKind.fiat,
                fiat: [
                  GetPaidFiatSettlementLeg(
                    amountMinor: null,
                    currency: 'USD',
                    orderId: '',
                    status: GetPaidSettlementLegStatus.pending,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('USD'), findsWidgets);
      expect(find.textContaining('Awaiting settlement'), findsOneWidget);
      // No fabricated fiat amount for a pending leg.
      expect(find.textContaining('0.00'), findsNothing);
    },
  );

  testWidgets(
    'a Lightning Address detail omits From-wallet and invents no chain fields',
    (tester) async {
      final transaction = _transaction(comment: 'note');
      await tester.pumpWidget(
        _app(GetPaidTransactionDetailScreen(transaction: transaction)),
      );
      await tester.pump();

      // Incoming Lightning Address payments have no funding wallet (report #12).
      expect(find.textContaining('From wallet'), findsNothing);
      // Nothing fabricated: no fees, sender, explorer links, txid, hashes, or
      // confirmations — the entity carries none of these.
      for (final forbidden in const [
        'Fee',
        'Sender',
        'Explorer',
        'Transaction ID',
        'Confirmations',
        'Payment hash',
        'Preimage',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
      // The receipt UUID is never surfaced as a chain txid.
      expect(find.textContaining(transaction.transactionId), findsNothing);
    },
  );

  testWidgets('a Lightning Address detail offers no View invoice action', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(GetPaidTransactionDetailScreen(transaction: _transaction())),
    );
    await tester.pump();

    expect(find.text('View invoice'), findsNothing);
  });
}
