import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/string_formatting.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_failure.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_invoice_facts.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_settlement.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_transaction.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_invoice_facts_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/usecases/look_up_get_paid_transaction_usecase.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_export_state.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_invoice_facts_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_transaction_detail_cubit.dart';
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

// The screen's export action reads a GetPaidExportCubit; a no-op stub keeps the
// history-rendering tests focused (the export flow has its own test).
class _StubExportCubit extends Cubit<GetPaidExportState>
    implements GetPaidExportCubit {
  int exportCalls = 0;

  _StubExportCubit() : super(const GetPaidExportState());

  @override
  Future<void> exportCsv() async => exportCalls++;
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
  final exportCubit = _StubExportCubit();
  addTearDown(exportCubit.close);
  await tester.pumpWidget(
    _app(
      MultiBlocProvider(
        providers: [
          BlocProvider<GetPaidTransactionHistoryCubit>.value(value: cubit),
          BlocProvider<GetPaidExportCubit>.value(value: exportCubit),
        ],
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

  testWidgets('row opens detail, where the comment and both ids are explicit', (
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
    final exportCubit = _StubExportCubit();
    addTearDown(exportCubit.close);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => MultiBlocProvider(
            providers: [
              BlocProvider<GetPaidTransactionHistoryCubit>.value(value: cubit),
              BlocProvider<GetPaidExportCubit>.value(value: exportCubit),
            ],
            child: const GetPaidTransactionHistoryScreen(),
          ),
          routes: [
            GoRoute(
              name: GetPaidDashboardRoute.getPaidTransactionDetail.name,
              path: 'detail',
              builder: (context, state) =>
                  _detailCard(state.extra! as GetPaidTransaction),
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
    // Both server ids are copyable rows of the card: the entry's receipt id and
    // the invoice it belongs to. Long identifiers are truncated in place.
    expect(
      find.text(StringFormatting.truncateMiddle(transaction.transactionId)),
      findsOneWidget,
    );
    expect(
      find.text(StringFormatting.truncateMiddle(transaction.invoiceId!)),
      findsOneWidget,
    );
    // The card IS the invoice: there is no action linking out to a second
    // invoice screen, and that route is never reached.
    expect(find.text('View invoice'), findsNothing);
    expect(find.text('invoice-${transaction.invoiceId}'), findsNothing);
    // Nothing resembling a private-link fragment is rendered.
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

    testWidgets('an unclassified row remains labeled by its captured rail', (
      tester,
    ) async {
      await _pumpHistory(
        tester,
        GetPaidTransactionHistoryState(
          status: GetPaidTransactionHistoryStatus.loaded,
          transactions: [_transaction()],
        ),
      );

      expect(find.text('Lightning'), findsOneWidget);
      expect(find.text('Mixed Fiat-BTC'), findsNothing);
    });

    testWidgets('an unavailable server kind falls back to the rail label', (
      tester,
    ) async {
      await _pumpHistory(
        tester,
        GetPaidTransactionHistoryState(
          status: GetPaidTransactionHistoryStatus.loaded,
          transactions: [_transaction(rail: GetPaidTransactionRail.liquid)],
        ),
      );

      // Never invent a settlement kind from current configuration.
      expect(find.text('Liquid'), findsOneWidget);
      expect(find.text('Mixed Fiat-BTC'), findsNothing);
    });
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
          _detailCard(
            _transaction(
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
      await tester.pumpWidget(_app(_detailCard(transaction)));
      await tester.pump();

      // Incoming Lightning Address payments have no funding wallet (report #12).
      expect(find.textContaining('From wallet'), findsNothing);
      // Nothing fabricated: no fees, sender, explorer links, chain txid, hashes,
      // or confirmations — the entity carries none of these.
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
      // The server's own id for the entry IS shown — labelled as the Bull
      // Bitcoin receipt id, never as a chain transaction id (the forbidden
      // 'Transaction ID' label above still finds nothing).
      expect(find.text('Receipt ID'), findsOneWidget);
      expect(
        find.text(StringFormatting.truncateMiddle(transaction.transactionId)),
        findsOneWidget,
      );
    },
  );

  testWidgets('a Lightning Address detail offers no View invoice action', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_detailCard(_transaction())));
    await tester.pump();

    expect(find.text('View invoice'), findsNothing);
    expect(find.byIcon(Icons.receipt_long), findsNothing);
  });
}

/// The card reads its invoice state from a cubit. These tests never wire an
/// invoice read, so it stays initial and the card renders exactly as it does for
/// an entry that carries no invoice.
Widget _detailCard(GetPaidTransaction transaction) => MultiBlocProvider(
  providers: [
    BlocProvider(
      create: (_) => GetPaidTransactionDetailCubit(
        _UnreadTransaction(),
        initialTransaction: transaction,
      ),
    ),
    BlocProvider(
      create: (_) =>
          GetPaidInvoiceFactsCubit(lookUpInvoiceFacts: _UnreadInvoiceFacts()),
    ),
  ],
  child: const GetPaidTransactionDetailScreen(),
);

class _UnreadInvoiceFacts implements LookUpGetPaidInvoiceFactsUsecase {
  @override
  Future<Result<GetPaidInvoiceFacts, GetPaidFailure>> execute({
    required String invoiceId,
  }) => throw UnimplementedError();
}

class _UnreadTransaction implements LookUpGetPaidTransactionUsecase {
  @override
  Future<Result<GetPaidTransaction, GetPaidFailure>> execute({
    required GetPaidTransactionSource source,
    required String transactionId,
  }) => throw UnimplementedError();
}
