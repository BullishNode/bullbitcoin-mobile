import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/get_paid/ui/screens/get_paid_dashboard_screen.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('Create a Lightning Address first'), findsOneWidget);
    verifyNever(() => findPaymentPage.execute(nym: any(named: 'nym')));
  });

  testWidgets('renders current address and payment page', (tester) async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenAnswer((_) async => 'alice@bullpay.ca');
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
