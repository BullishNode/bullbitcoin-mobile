import 'package:bb_mobile/generated/l10n/localization.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/payment_page_router.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/get_paid_router.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _MockLightningAddressFacade extends Mock
    implements LightningAddressFacade {}

class _MockFindPaymentPageUsecase extends Mock
    implements FindPaymentPageUsecase {}

void main() {
  late _MockLightningAddressFacade lightningAddressFacade;
  late _MockFindPaymentPageUsecase findPaymentPage;

  setUp(() {
    lightningAddressFacade = _MockLightningAddressFacade();
    findPaymentPage = _MockFindPaymentPageUsecase();
  });

  testWidgets('keeps invoices available when Lightning Address is absent', (
    tester,
  ) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => null);
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => null);

    await tester.pumpWidget(
      _harness(
        lightningAddressFacade: lightningAddressFacade,
        findPaymentPage: findPaymentPage,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Lightning Address'), findsOneWidget);
    expect(find.text('Not set up'), findsWidgets);
    expect(find.text('Payment Page'), findsOneWidget);
    expect(find.text('Choose a Bullnym name first'), findsOneWidget);
    expect(find.text('Create and manage invoices'), findsOneWidget);
    expect(find.text('BTCPay'), findsOneWidget);
    expect(find.text('Connect BTCPay Server'), findsOneWidget);
    verifyNever(() => findPaymentPage.execute(nym: any(named: 'nym')));
  });

  testWidgets('renders current address and payment page', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => 'alice');
    when(
      () => findPaymentPage.execute(nym: 'alice'),
    ).thenAnswer((_) async => _page());

    await tester.pumpWidget(
      _harness(
        lightningAddressFacade: lightningAddressFacade,
        findPaymentPage: findPaymentPage,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('alice@bullpay.ca'), findsOneWidget);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
    expect(find.text('Active'), findsNWidgets(2));
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Open'), findsNothing);
  });

  testWidgets('refreshes when editor route pops true', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => 'alice');
    var refreshCount = 0;
    when(() => findPaymentPage.execute(nym: 'alice')).thenAnswer((_) async {
      refreshCount += 1;
      return refreshCount == 1 ? null : _page();
    });

    final router = GoRouter(
      initialLocation: '/get-paid',
      routes: [
        GoRoute(
          path: '/get-paid',
          builder: (context, state) => BlocProvider(
            create: (_) => GetPaidDashboardCubit(
              lightningAddressFacade: lightningAddressFacade,
              findPaymentPage: findPaymentPage,
            ),
            child: const GetPaidDashboardScreen(),
          ),
          routes: [
            GoRoute(
              name: PaymentPageRoute.editor.name,
              path: PaymentPageRoute.editor.path,
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Finish'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Payment Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    verify(() => findPaymentPage.execute(nym: 'alice')).called(2);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
  });

  testWidgets('opens invoices route without a Lightning Address', (
    tester,
  ) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => null);
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => null);

    final router = GoRouter(
      initialLocation: '/get-paid',
      routes: [
        GoRoute(
          path: '/get-paid',
          builder: (context, state) => BlocProvider(
            create: (_) => GetPaidDashboardCubit(
              lightningAddressFacade: lightningAddressFacade,
              findPaymentPage: findPaymentPage,
            ),
            child: const GetPaidDashboardScreen(),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.home.name,
              path: InvoicesRoute.home.path,
              builder: (context, state) =>
                  const Scaffold(body: Text('Invoices home')),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();

    expect(find.text('Invoices home'), findsOneWidget);
    verifyNever(() => findPaymentPage.execute(nym: any(named: 'nym')));
  });

  testWidgets('opens Get Paid settings route', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => null);
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => null);

    final router = GoRouter(
      initialLocation: '/get-paid',
      routes: [
        GoRoute(
          path: '/get-paid',
          builder: (context, state) => BlocProvider(
            create: (_) => GetPaidDashboardCubit(
              lightningAddressFacade: lightningAddressFacade,
              findPaymentPage: findPaymentPage,
            ),
            child: const GetPaidDashboardScreen(),
          ),
          routes: [
            GoRoute(
              name: GetPaidRoute.settings.name,
              path: GetPaidRoute.settings.path,
              builder: (context, state) =>
                  const Scaffold(body: Text('Get Paid settings route')),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Get Paid settings'));
    await tester.pumpAndSettle();

    expect(find.text('Get Paid settings route'), findsOneWidget);
  });

  testWidgets('refreshes when invoices route pops true', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => 'alice');
    var refreshCount = 0;
    when(() => findPaymentPage.execute(nym: 'alice')).thenAnswer((_) async {
      refreshCount += 1;
      return refreshCount == 1 ? null : _page();
    });

    final router = GoRouter(
      initialLocation: '/get-paid',
      routes: [
        GoRoute(
          path: '/get-paid',
          builder: (context, state) => BlocProvider(
            create: (_) => GetPaidDashboardCubit(
              lightningAddressFacade: lightningAddressFacade,
              findPaymentPage: findPaymentPage,
            ),
            child: const GetPaidDashboardScreen(),
          ),
          routes: [
            GoRoute(
              name: InvoicesRoute.home.name,
              path: InvoicesRoute.home.path,
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Close invoices changed'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Invoices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close invoices changed'));
    await tester.pumpAndSettle();

    verify(() => findPaymentPage.execute(nym: 'alice')).called(2);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
  });

  testWidgets('refreshes wallets and dashboard when BTCPay route pops true', (
    tester,
  ) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => 'alice');
    var refreshCount = 0;
    when(() => findPaymentPage.execute(nym: 'alice')).thenAnswer((_) async {
      refreshCount += 1;
      return refreshCount == 1 ? null : _page();
    });
    var walletRefreshCount = 0;

    final router = GoRouter(
      initialLocation: '/get-paid',
      routes: [
        GoRoute(
          path: '/get-paid',
          builder: (context, state) => BlocProvider(
            create: (_) => GetPaidDashboardCubit(
              lightningAddressFacade: lightningAddressFacade,
              findPaymentPage: findPaymentPage,
            ),
            child: GetPaidDashboardScreen(
              onExternalReceiveWalletsCreated: () => walletRefreshCount += 1,
            ),
          ),
          routes: [
            GoRoute(
              name: GetPaidRoute.btcpayPairing.name,
              path: GetPaidRoute.btcpayPairing.path,
              builder: (context, state) => Scaffold(
                body: TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('Close BTCPay changed'),
                ),
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('BTCPay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close BTCPay changed'));
    await tester.pumpAndSettle();

    expect(walletRefreshCount, 1);
    verify(() => findPaymentPage.execute(nym: 'alice')).called(2);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
  });
}

Widget _harness({
  required LightningAddressFacade lightningAddressFacade,
  required FindPaymentPageUsecase findPaymentPage,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => GetPaidDashboardCubit(
        lightningAddressFacade: lightningAddressFacade,
        findPaymentPage: findPaymentPage,
      ),
      child: const GetPaidDashboardScreen(),
    ),
  );
}

Widget _routerHarness(GoRouter router) {
  return MaterialApp.router(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
  );
}

PaymentPage _page() {
  return const PaymentPage(
    nym: 'alice',
    header: "Alice's Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: null,
    twitter: null,
    instagram: null,
    enabled: true,
    isArchived: false,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/alice',
  );
}
