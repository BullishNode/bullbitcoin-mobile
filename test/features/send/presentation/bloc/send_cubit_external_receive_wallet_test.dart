import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'send_cubit_harness.dart';

void main() {
  test('first classification failure does not load sendable wallets', () async {
    final harness = SendCubitHarness();
    final manual = sendCubitWallet(id: 'manual-wallet', label: 'Cold Storage');
    harness.stubWallets([manual]);
    when(
      () => harness.externalReceiveWallets.idsForWallets(any()),
    ).thenThrow(Exception('origin unavailable'));

    final cubit = harness.createCubit();
    addTearDown(cubit.close);

    await cubit.loadWalletWithRatesAndFees();

    expect(cubit.state.wallets, isEmpty);
    expect(cubit.state.error, contains('origin unavailable'));
  });

  test(
    'later classification failure preserves known external receive ids',
    () async {
      final harness = SendCubitHarness();
      final manual = sendCubitWallet(
        id: 'manual-wallet',
        label: 'Cold Storage',
      );
      final lightningAddress = sendCubitWallet(
        id: 'lightning-address',
        label: 'Lightning Address-LBTC',
      );
      final paymentPage = sendCubitWallet(
        id: 'payment-page',
        label: 'Payment Page-LBTC',
      );
      harness.stubWallets([manual, lightningAddress, paymentPage]);
      var calls = 0;
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          return ExternalReceiveWalletIds(
            purposeByWalletId: {
              lightningAddress.id:
                  ExternalReceiveWalletPurpose.lightningAddress,
              paymentPage.id: ExternalReceiveWalletPurpose.paymentPage,
            },
          );
        }
        throw Exception('origin unavailable');
      });

      final cubit = harness.createCubit();
      addTearDown(cubit.close);

      await cubit.loadWalletWithRatesAndFees();
      expect(cubit.state.wallets.map((wallet) => wallet.id), [manual.id]);

      await cubit.loadWalletWithRatesAndFees();
      expect(cubit.state.wallets.map((wallet) => wallet.id), [manual.id]);
    },
  );
}
