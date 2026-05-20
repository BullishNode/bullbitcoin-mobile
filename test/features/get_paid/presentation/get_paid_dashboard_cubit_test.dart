import 'dart:async';

import 'package:bb_mobile/features/get_paid/payment_page/application/payment_page_application_error.dart';
import 'package:bb_mobile/features/get_paid/payment_page/application/usecases/find_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/payment_page/domain/entities/payment_page.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_dashboard_cubit.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLightningAddressFacade extends Mock
    implements LightningAddressFacade {}

class _MockFindPaymentPageUsecase extends Mock
    implements FindPaymentPageUsecase {}

void main() {
  late _MockLightningAddressFacade lightningAddressFacade;
  late _MockFindPaymentPageUsecase findPaymentPage;
  late GetPaidDashboardCubit cubit;

  setUp(() {
    lightningAddressFacade = _MockLightningAddressFacade();
    findPaymentPage = _MockFindPaymentPageUsecase();
    cubit = GetPaidDashboardCubit(
      lightningAddressFacade: lightningAddressFacade,
      findPaymentPage: findPaymentPage,
    );
  });

  tearDown(() => cubit.close());

  test(
    'refresh skips payment page lookup when Lightning Address is absent',
    () async {
      when(
        () => lightningAddressFacade.getCurrentLightningAddress(),
      ).thenAnswer((_) async => null);
      await cubit.refresh();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.lightningAddress, isNull);
      expect(cubit.state.paymentPage, isNull);
      verifyNever(() => findPaymentPage.execute(nym: any(named: 'nym')));
    },
  );

  test(
    'refresh loads payment page for current Lightning Address nym',
    () async {
      when(
        () => lightningAddressFacade.getCurrentLightningAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => findPaymentPage.execute(nym: 'alice'),
      ).thenAnswer((_) async => _page());

      await cubit.refresh();

      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.paymentPage?.publicUrl, 'https://bullpay.ca/alice');
      expect(cubit.state.hasPaymentPage, isTrue);
    },
  );

  test(
    'refresh keeps Lightning Address when payment page is missing',
    () async {
      when(
        () => lightningAddressFacade.getCurrentLightningAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => findPaymentPage.execute(nym: 'alice'),
      ).thenAnswer((_) async => null);

      await cubit.refresh();

      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.paymentPage, isNull);
      expect(cubit.state.hasPaymentPage, isFalse);
    },
  );

  test(
    'refresh maps payment page errors without clearing Lightning Address',
    () async {
      when(
        () => lightningAddressFacade.getCurrentLightningAddress(),
      ).thenAnswer((_) async => 'alice@bullpay.ca');
      when(
        () => findPaymentPage.execute(nym: 'alice'),
      ).thenThrow(const PaymentPageNetworkError('network down'));

      await cubit.refresh();

      expect(cubit.state.lightningAddress, 'alice@bullpay.ca');
      expect(cubit.state.nym, 'alice');
      expect(cubit.state.error, isNot(contains('network down')));
      expect(cubit.state.error, 'Network error. Check your connection.');
      expect(cubit.state.isLoading, isFalse);
    },
  );

  test('refresh maps generic exceptions to friendly copy', () async {
    when(
      () => lightningAddressFacade.getCurrentLightningAddress(),
    ).thenThrow(Exception('socket details'));

    await cubit.refresh();

    expect(cubit.state.error, 'Something went wrong. Please try again.');
    expect(cubit.state.error, isNot(contains('socket details')));
    expect(cubit.state.isLoading, isFalse);
  });

  test('refresh ignores stale results from older requests', () async {
    final firstAddress = Completer<String?>();
    final secondAddress = Completer<String?>();
    final secondPage = Completer<PaymentPage?>();
    var addressCalls = 0;

    when(() => lightningAddressFacade.getCurrentLightningAddress()).thenAnswer((
      _,
    ) {
      addressCalls += 1;
      return addressCalls == 1 ? firstAddress.future : secondAddress.future;
    });
    when(
      () => findPaymentPage.execute(nym: 'bob'),
    ).thenAnswer((_) => secondPage.future);

    final firstRefresh = cubit.refresh();
    final secondRefresh = cubit.refresh();

    secondAddress.complete('bob@bullpay.ca');
    secondPage.complete(_page(nym: 'bob'));
    await secondRefresh;

    expect(cubit.state.lightningAddress, 'bob@bullpay.ca');
    expect(cubit.state.nym, 'bob');
    expect(cubit.state.paymentPage?.publicUrl, 'https://bullpay.ca/bob');

    firstAddress.complete('alice@bullpay.ca');
    await firstRefresh;

    expect(cubit.state.lightningAddress, 'bob@bullpay.ca');
    expect(cubit.state.nym, 'bob');
    expect(cubit.state.paymentPage?.publicUrl, 'https://bullpay.ca/bob');
    verifyNever(() => findPaymentPage.execute(nym: 'alice'));
  });
}

PaymentPage _page({String nym = 'alice'}) {
  return PaymentPage(
    nym: nym,
    header: "${nym[0].toUpperCase()}${nym.substring(1)}'s Coffee",
    description: 'Tips welcome',
    displayCurrency: 'CAD',
    website: null,
    twitter: null,
    instagram: null,
    enabled: true,
    isArchived: false,
    avatarSha256: null,
    ogSha256: null,
    publicUrl: 'https://bullpay.ca/$nym',
  );
}
