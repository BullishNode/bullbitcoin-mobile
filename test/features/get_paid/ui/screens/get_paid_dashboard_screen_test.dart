import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/payment_page/ui/payment_page_router.dart';
import 'package:bb_mobile/features/get_paid/invoices/ui/invoices_router.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
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

  testWidgets('renders setup state when Lightning Address is absent', (
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
    expect(find.text('Create a Lightning Address first'), findsNWidgets(2));
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
    expect(find.text('Edit'), findsOneWidget);
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

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    verify(() => findPaymentPage.execute(nym: 'alice')).called(2);
    expect(find.text('https://bullpay.ca/alice'), findsOneWidget);
  });

  testWidgets('opens invoices route from dashboard slot', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
    when(
      () => lightningAddressFacade.getCurrentNym(),
    ).thenAnswer((_) async => 'alice');
    when(
      () => findPaymentPage.execute(nym: 'alice'),
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
              name: InvoicesRoute.list.name,
              path: InvoicesRoute.list.path,
              builder: (context, state) =>
                  const Scaffold(body: Text('Invoices list')),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Invoices list'), findsOneWidget);
  });
}

Widget _harness({
  required LightningAddressFacade lightningAddressFacade,
  required FindPaymentPageUsecase findPaymentPage,
}) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => GetPaidDashboardCubit(
        lightningAddressFacade: lightningAddressFacade,
        findPaymentPage: findPaymentPage,
      ),
      child: const GetPaidDashboardScreen(),
    ),
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
