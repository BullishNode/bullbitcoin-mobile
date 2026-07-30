import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/invoices/public/invoices_routes.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bull_ui/bull_ui.dart' show BullButton, BullTopBar;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Stub cubit seeded with a fixed state; refresh() is a no-op so the seeded
// state renders without a locator or the real facades.
class _StubCubit extends Cubit<GetPaidDashboardState>
    implements GetPaidDashboardCubit {
  int refreshCalls = 0;

  _StubCubit(super.initialState);

  @override
  Future<void> refresh() async => refreshCalls++;
}

Future<void> _pump(WidgetTester tester, GetPaidDashboardState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.themeData(AppThemeType.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: BlocProvider<GetPaidDashboardCubit>.value(
        value: _StubCubit(state),
        child: const GetPaidDashboardScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the hub renders Transactions plus five product cards', (
    tester,
  ) async {
    await _pump(tester, const GetPaidDashboardState());

    expect(find.byType(BullTopBar), findsOneWidget);
    expect(find.byType(GetPaidSlotCard), findsNWidgets(6));
    expect(find.text('Transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first load shows cards with in-card progress indicators', (
    tester,
  ) async {
    await _pump(tester, const GetPaidDashboardState(isLoading: true));

    expect(find.byType(GetPaidSlotCard), findsNWidgets(6));
    expect(find.byType(CircularProgressIndicator), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('only unresolved cards retain progress indicators', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidDashboardState(
        lightningStatus: GetPaidProductStatus.absent,
        invoicesStatus: GetPaidDashboardCardStatus.loaded,
        btcpayStatus: GetPaidDashboardCardStatus.loaded,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Invoices card opens invoice creation directly', (tester) async {
    final cubit = _StubCubit(const GetPaidDashboardState());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              BlocProvider<GetPaidDashboardCubit>.value(
                value: cubit,
                child: const GetPaidDashboardScreen(),
              ),
        ),
        GoRoute(
          name: InvoicesRoute.create.name,
          path: '/invoice-create',
          builder: (context, state) =>
              const Scaffold(body: Text('invoice-create-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();

    expect(find.text('invoice-create-destination'), findsOneWidget);
  });

  testWidgets('the invoices card shows pending fallback attention', (
    tester,
  ) async {
    await _pump(
      tester,
      const GetPaidDashboardState(
        invoicesWalletReady: true,
        fallbackAttentionCount: 2,
      ),
    );

    expect(find.text('2 SETTLEMENTS PENDING'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending fallback attention opens the invoice list', (
    tester,
  ) async {
    final cubit = _StubCubit(
      const GetPaidDashboardState(
        invoicesWalletReady: true,
        fallbackAttentionCount: 1,
      ),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              BlocProvider<GetPaidDashboardCubit>.value(
                value: cubit,
                child: const GetPaidDashboardScreen(),
              ),
        ),
        GoRoute(
          name: InvoicesRoute.list.name,
          path: '/invoices',
          builder: (context, state) =>
              const Scaffold(body: Text('invoice-list-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();

    expect(find.text('invoice-list-destination'), findsOneWidget);
  });

  testWidgets(
    'unavailable invoice supervision keeps navigation and retry separate',
    (tester) async {
      final cubit = _StubCubit(
        const GetPaidDashboardState(
          invoicesUnavailable: true,
          invoicesWalletReady: true,
          fallbackAttentionCount: 2,
          invoicesStatus: GetPaidDashboardCardStatus.loaded,
        ),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                BlocProvider<GetPaidDashboardCubit>.value(
                  value: cubit,
                  child: const GetPaidDashboardScreen(),
                ),
          ),
          GoRoute(
            name: InvoicesRoute.list.name,
            path: '/invoices',
            builder: (context, state) =>
                const Scaffold(body: Text('invoice-list-destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(cubit.close);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.themeData(AppThemeType.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
        ),
      );
      await tester.pump();

      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.text('2 SETTLEMENTS PENDING'), findsNothing);
      final priorRefreshes = cubit.refreshCalls;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(cubit.refreshCalls, priorRefreshes + 1);

      await tester.tap(find.text('Invoices'));
      await tester.pumpAndSettle();
      expect(find.text('invoice-list-destination'), findsOneWidget);
    },
  );

  testWidgets('Transactions card opens received Get Paid history', (
    tester,
  ) async {
    final cubit = _StubCubit(const GetPaidDashboardState());
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              BlocProvider<GetPaidDashboardCubit>.value(
                value: cubit,
                child: const GetPaidDashboardScreen(),
              ),
        ),
        GoRoute(
          name: GetPaidDashboardRoute.getPaidTransactions.name,
          path: '/transactions',
          builder: (context, state) =>
              const Scaffold(body: Text('transactions-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.themeData(AppThemeType.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();

    expect(find.text('transactions-destination'), findsOneWidget);
  });

  group('settlement badges', () {
    GetPaidPaymentPageSnapshot activePage() => const GetPaidPaymentPageSnapshot(
      publicUrl: 'https://pay.example/satoshi',
      isArchived: false,
    );

    GetPaidPosTerminalSnapshot activePos() => const GetPaidPosTerminalSnapshot(
      terminalUrl: 'https://pos.example/satoshi/pos',
      isArchived: false,
    );

    GetPaidDashboardSettlementConfig config(int pct, {String? currency}) =>
        GetPaidDashboardSettlementConfig(
          fiatPercentage: pct,
          currencyCode: currency,
        );

    GetPaidDashboardState activeState({
      Map<GetPaidDashboardSettlementProduct, GetPaidDashboardSettlementConfig>?
      settlement,
      bool unavailable = false,
    }) => GetPaidDashboardState(
      lightningAddress: 'satoshi@bull.money',
      lightningActive: true,
      nym: 'satoshi',
      paymentPage: activePage(),
      posTerminal: activePos(),
      fiatSettlement: settlement,
      fiatSettlementUnavailable: unavailable,
    );

    testWidgets('each active product card shows its confirmed settlement '
        'summary as a dedicated badge', (tester) async {
      await _pump(
        tester,
        activeState(
          settlement: {
            GetPaidDashboardSettlementProduct.lightningAddress: config(0),
            GetPaidDashboardSettlementProduct.paymentPage: config(
              100,
              currency: 'CAD',
            ),
            GetPaidDashboardSettlementProduct.pos: config(50, currency: 'CAD'),
          },
        ),
      );

      // Bitcoin-only IS shown (owner report #6), plus fiat-only and mixed.
      expect(find.text('Bitcoin only'), findsOneWidget);
      expect(find.text('100% fiat · CAD'), findsOneWidget);
      expect(find.text('50% Bitcoin · 50% fiat · CAD'), findsOneWidget);
      // The URL subtitle stays a separate line — the badge is not concatenated.
      expect(find.text('https://pay.example/satoshi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a settlement read failure renders the unavailable badge on '
        'active cards, never a Bitcoin-only guess', (tester) async {
      await _pump(tester, activeState(unavailable: true));

      expect(find.text('Settlement unavailable'), findsNWidgets(3));
      expect(find.text('Bitcoin only'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inactive products show no settlement badge', (tester) async {
      await _pump(
        tester,
        const GetPaidDashboardState(fiatSettlementUnavailable: true),
      );

      expect(find.text('Settlement unavailable'), findsNothing);
      expect(find.text('Bitcoin only'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('UX-2 product states', () {
    testWidgets('the Get Paid settings gear is removed from the top bar', (
      tester,
    ) async {
      await _pump(tester, const GetPaidDashboardState());

      expect(find.byIcon(Icons.settings), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an archived product shows an Archived status chip', (
      tester,
    ) async {
      await _pump(
        tester,
        GetPaidDashboardState(
          paymentPage: const GetPaidPaymentPageSnapshot(
            publicUrl: 'https://pay.example/satoshi',
            isArchived: true,
          ),
          paymentPageStatus: GetPaidProductStatus.archived,
        ),
      );

      expect(find.text('ARCHIVED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unavailable product shows Unavailable and a Retry action', (
      tester,
    ) async {
      await _pump(
        tester,
        const GetPaidDashboardState(
          posStatus: GetPaidProductStatus.unavailable,
        ),
      );

      expect(find.text('UNAVAILABLE'), findsOneWidget);
      // Retry is a BullButton (RichText label) inside the still-tappable card.
      expect(
        find.byWidgetPredicate((w) => w is BullButton && w.label == 'Retry'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an absent product shows a Not set up chip', (tester) async {
      await _pump(
        tester,
        const GetPaidDashboardState(posStatus: GetPaidProductStatus.absent),
      );

      expect(find.text('NOT SET UP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a self-heal failure shows the missing-wallet warning', (
      tester,
    ) async {
      await _pump(
        tester,
        GetPaidDashboardState(
          posTerminal: const GetPaidPosTerminalSnapshot(
            terminalUrl: 'https://pos.example/satoshi/pos',
            isArchived: false,
          ),
          posStatus: GetPaidProductStatus.active,
          posWalletWarning: true,
        ),
      );

      expect(find.text('Wallet needs attention'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'BTCPay refresh failure overrides a stale connection with unavailable',
      (tester) async {
        await _pump(
          tester,
          const GetPaidDashboardState(
            btcpayConnection: GetPaidBtcpayConnectionSnapshot(
              serverUrl: 'https://stale-btcpay.example',
            ),
            btcpayStatus: GetPaidDashboardCardStatus.loaded,
            btcpayUnavailable: true,
          ),
        );

        expect(find.text('UNAVAILABLE'), findsOneWidget);
        expect(find.text('ACTIVE'), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is BullButton && w.label == 'Retry'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
