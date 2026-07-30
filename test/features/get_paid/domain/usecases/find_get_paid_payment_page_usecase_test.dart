import 'package:bb_mobile/features/get_paid/domain/usecases/find_get_paid_payment_page_usecase.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_dashboard_snapshot.dart';
import 'package:bb_mobile/features/get_paid/domain/get_paid_product_probe.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps a Donation Page into the facts owned by Get Paid', () async {
    final usecase = FindGetPaidPaymentPageUsecase(
      paymentPage: _facade(
        ({required nym}) async => PaymentPage(
          nym: nym,
          header: 'Donate',
          description: 'Description',
          displayCurrency: 'CAD',
          enabled: true,
          isArchived: false,
          publicUrl: 'https://pay.example/$nym',
        ),
      ),
    );

    final result = await usecase.execute(nym: 'alice');

    expect(result, isA<GetPaidProductFound<GetPaidPaymentPageSnapshot>>());
    final snapshot =
        (result as GetPaidProductFound<GetPaidPaymentPageSnapshot>).row;
    expect(snapshot.publicUrl, 'https://pay.example/alice');
    expect(snapshot.isArchived, isFalse);
  });

  test('keeps confirmed absence distinct from an unavailable read', () async {
    final absent = FindGetPaidPaymentPageUsecase(
      paymentPage: _facade(({required nym}) async => null),
    );
    final unavailable = FindGetPaidPaymentPageUsecase(
      paymentPage: _facade(({required nym}) async => throw Exception('down')),
    );

    expect(
      await absent.execute(nym: 'alice'),
      isA<GetPaidProductAbsent<GetPaidPaymentPageSnapshot>>(),
    );
    expect(
      await unavailable.execute(nym: 'alice'),
      isA<GetPaidProductUnavailable<GetPaidPaymentPageSnapshot>>(),
    );
  });
}

PaymentPageFacade _facade(
  Future<PaymentPage?> Function({required String nym}) find,
) => PaymentPageFacade(
  find: find,
  save: (command) async => throw UnimplementedError(),
  archive: () async => throw UnimplementedError(),
  supportedCurrencies: () async => throw UnimplementedError(),
  ensurePageLive: () async => throw UnimplementedError(),
  prepareWallet: () async => throw UnimplementedError(),
);
