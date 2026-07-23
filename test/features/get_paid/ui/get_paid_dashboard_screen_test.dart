import 'package:bb_mobile/core/themes/app_theme.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_state.dart';
import 'package:bb_mobile/features/get_paid/public/get_paid_routes.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/features/get_paid/ui/widgets/get_paid_slot_card.dart';
import 'package:bb_mobile/features/fiat_settlement/public/fiat_settlement_facade.dart';
import 'package:bb_mobile/features/invoices/public/invoices_routes.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bull_ui/bull_ui.dart' show BullTopBar;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Stub cubit seeded with a fixed state; refresh() is a no-op so the seeded
// state renders without a locator or the real facades.
class _StubCubit extends Cubit<GetPaidDashboardState>
    implements GetPaidDashboardCubit {
  _StubCubit(super.initialState);

  @override
  Future<void> refresh() async {}
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
        lightningStatus: GetPaidDashboardCardStatus.loaded,
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
    PaymentPage activePage() => PaymentPage(
      nym: 'satoshi',
      header: 'Donate',
      description: 'desc',
      displayCurrency: 'CAD',
      enabled: true,
      isArchived: false,
      publicUrl: 'https://pay.example/satoshi',
    );

    PosTerminal activePos() => PosTerminal(
      nym: 'satoshi',
      label: 'Till',
      displayCurrency: 'CAD',
      enabled: true,
      isArchived: false,
      terminalUrl: 'https://pos.example/satoshi/pos',
    );

    FiatSettlementProductConfig config(
      FiatSettlementProduct product,
      int pct, {
      FiatCurrency? currency,
    }) => FiatSettlementProductConfig(
      product: product,
      fiatPercentage: pct,
      currency: currency,
    );

    GetPaidDashboardState activeState({
      Map<FiatSettlementProduct, FiatSettlementProductConfig>? settlement,
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
            FiatSettlementProduct.lightningAddress: config(
              FiatSettlementProduct.lightningAddress,
              0,
            ),
            FiatSettlementProduct.paymentPage: config(
              FiatSettlementProduct.paymentPage,
              100,
              currency: FiatCurrency.cad,
            ),
            FiatSettlementProduct.pos: config(
              FiatSettlementProduct.pos,
              50,
              currency: FiatCurrency.cad,
            ),
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
}
