import 'package:bb_mobile/features/get_paid_settings/public/get_paid_settings_facade.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/get_payment_page_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/payment_page/domain/usecases/update_payment_page_wallet_behavior_usecase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pins reads to the Donation Page product', () async {
    GetPaidWalletProduct? requested;
    final facade = _facade(
      read: ({only}) async {
        requested = only;
        return [_behavior(GetPaidWalletProduct.paymentPage)];
      },
    );

    final value = await GetPaymentPageWalletBehaviorUsecase(
      getPaidSettings: facade,
    ).execute();

    expect(requested, GetPaidWalletProduct.paymentPage);
    expect(value, isA<PaymentPageWalletBehaviorFound>());
    expect(
      (value as PaymentPageWalletBehaviorFound).behavior.walletId,
      'wallet-1',
    );
  });

  test('keeps confirmed absence distinct from an unavailable read', () async {
    final value = await GetPaymentPageWalletBehaviorUsecase(
      getPaidSettings: _facade(),
    ).execute();

    expect(value, isA<PaymentPageWalletBehaviorAbsent>());
  });

  test('maps a settings read exception to unavailable', () async {
    final value = await GetPaymentPageWalletBehaviorUsecase(
      getPaidSettings: _facade(read: ({only}) async => throw Exception('down')),
    ).execute();

    expect(value, isA<PaymentPageWalletBehaviorUnavailable>());
  });

  test('does not convert programmer errors into unavailable', () async {
    final future = GetPaymentPageWalletBehaviorUsecase(
      getPaidSettings: _facade(read: ({only}) async => throw StateError('bug')),
    ).execute();

    await expectLater(future, throwsA(isA<StateError>()));
  });

  test('maps a settings write failure to false', () async {
    final facade = _facade(
      update: ({required walletId, hideOnHome, autoSweepEnabled}) async {
        throw Exception('write failed');
      },
    );

    final saved = await UpdatePaymentPageWalletBehaviorUsecase(
      getPaidSettings: facade,
    ).execute(walletId: 'wallet-1', autoSweepEnabled: true);

    expect(saved, isFalse);
  });
}

GetPaidSettingsFacade _facade({
  Future<List<GetPaidWalletBehavior>> Function({GetPaidWalletProduct? only})?
  read,
  Future<void> Function({
    required String walletId,
    bool? hideOnHome,
    bool? autoSweepEnabled,
  })?
  update,
}) => GetPaidSettingsFacade(
  walletBehaviors: read ?? ({only}) async => const [],
  updateWalletBehavior:
      update ?? ({required walletId, hideOnHome, autoSweepEnabled}) async {},
);

GetPaidWalletBehavior _behavior(GetPaidWalletProduct product) =>
    GetPaidWalletBehavior(
      product: product,
      walletId: 'wallet-1',
      hideOnHome: false,
      autoSweepEnabled: true,
    );
