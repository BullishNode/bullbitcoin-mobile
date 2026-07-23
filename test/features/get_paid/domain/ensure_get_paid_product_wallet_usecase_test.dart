import 'package:bb_mobile/features/get_paid/domain/ensure_get_paid_product_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/payment_page/public/payment_page_facade.dart';
import 'package:bb_mobile/features/pos/public/pos_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLightningAddress extends Mock implements LightningAddressFacade {}

class _MockPaymentPage extends Mock implements PaymentPageFacade {}

class _MockPos extends Mock implements PosFacade {}

void main() {
  late _MockLightningAddress lightningAddress;
  late _MockPaymentPage paymentPage;
  late _MockPos pos;
  late EnsureGetPaidProductWalletUsecase usecase;

  setUp(() {
    lightningAddress = _MockLightningAddress();
    paymentPage = _MockPaymentPage();
    pos = _MockPos();
    usecase = EnsureGetPaidProductWalletUsecase(
      lightningAddress,
      paymentPage,
      pos,
    );
  });

  void stubLightning({bool? created, Object? error}) {
    if (error != null) {
      when(() => lightningAddress.prepareWallet()).thenThrow(error);
    } else {
      when(() => lightningAddress.prepareWallet()).thenAnswer(
        (_) async => PreparedLightningAddressWallet(
          walletId: 'la-wallet',
          ctDescriptor: 'ct(la)',
          created: created!,
        ),
      );
    }
  }

  void stubPaymentPage({bool? created, Object? error}) {
    if (error != null) {
      when(() => paymentPage.prepareWallet()).thenThrow(error);
    } else {
      when(() => paymentPage.prepareWallet()).thenAnswer(
        (_) async => PreparedPaymentPageWallet(
          walletId: 'page-wallet',
          ctDescriptor: 'ct(page)',
          created: created!,
        ),
      );
    }
  }

  void stubPos({bool? created, Object? error}) {
    if (error != null) {
      when(() => pos.prepareWallet()).thenThrow(error);
    } else {
      when(() => pos.prepareWallet()).thenAnswer(
        (_) async => PreparedPosWallet(
          walletId: 'pos-wallet',
          ctDescriptor: 'ct(pos)',
          created: created!,
        ),
      );
    }
  }

  test(
    'an already-present wallet is reported present (idempotent no-op)',
    () async {
      stubLightning(created: false);
      stubPaymentPage(created: false);
      stubPos(created: false);

      expect(
        await usecase.execute(GetPaidWalletBackedProduct.lightningAddress),
        GetPaidProductWalletOutcome.present,
      );
      expect(
        await usecase.execute(GetPaidWalletBackedProduct.paymentPage),
        GetPaidProductWalletOutcome.present,
      );
      expect(
        await usecase.execute(GetPaidWalletBackedProduct.pos),
        GetPaidProductWalletOutcome.present,
      );
    },
  );

  test('a missing wallet is re-derived and reported rederived', () async {
    stubLightning(created: true);
    stubPaymentPage(created: true);
    stubPos(created: true);

    expect(
      await usecase.execute(GetPaidWalletBackedProduct.lightningAddress),
      GetPaidProductWalletOutcome.rederived,
    );
    expect(
      await usecase.execute(GetPaidWalletBackedProduct.paymentPage),
      GetPaidProductWalletOutcome.rederived,
    );
    expect(
      await usecase.execute(GetPaidWalletBackedProduct.pos),
      GetPaidProductWalletOutcome.rederived,
    );
    verify(() => paymentPage.prepareWallet()).called(1);
    verify(() => pos.prepareWallet()).called(1);
  });

  test('a derivation failure is reported failed, never thrown', () async {
    stubLightning(error: Exception('derivation failed'));
    stubPaymentPage(error: Exception('derivation failed'));
    stubPos(error: Exception('derivation failed'));

    expect(
      await usecase.execute(GetPaidWalletBackedProduct.lightningAddress),
      GetPaidProductWalletOutcome.failed,
    );
    expect(
      await usecase.execute(GetPaidWalletBackedProduct.paymentPage),
      GetPaidProductWalletOutcome.failed,
    );
    expect(
      await usecase.execute(GetPaidWalletBackedProduct.pos),
      GetPaidProductWalletOutcome.failed,
    );
  });

  test('each product delegates to its own facade only', () async {
    stubPaymentPage(created: false);

    await usecase.execute(GetPaidWalletBackedProduct.paymentPage);

    verify(() => paymentPage.prepareWallet()).called(1);
    verifyNever(() => lightningAddress.prepareWallet());
    verifyNever(() => pos.prepareWallet());
  });
}
