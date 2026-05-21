import 'package:bb_mobile/core/utils/payment_request.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'send_cubit_harness.dart';

void main() {
  setUpAll(registerSendCubitHarnessFallbacks);

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

  test(
    'preselected external receive wallet cannot fall back to best wallet',
    () async {
      final harness = SendCubitHarness();
      final manual = sendCubitWallet(
        id: 'manual-wallet',
        label: 'Cold Storage',
      );
      final paymentPage = sendCubitWallet(
        id: 'payment-page',
        label: 'Payment Page-LBTC',
      );
      harness.stubWallets([manual, paymentPage]);
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: {
            paymentPage.id: ExternalReceiveWalletPurpose.paymentPage,
          },
        ),
      );

      final cubit = harness.createCubit(wallet: paymentPage);
      addTearDown(cubit.close);

      await cubit.loadWalletWithRatesAndFees();
      expect(cubit.state.wallets.map((wallet) => wallet.id), [manual.id]);
      expect(cubit.state.error, 'This wallet cannot be used for sending.');

      harness.seed(
        cubit,
        cubit.state.copyWith(
          paymentRequest: const PaymentRequest.liquid(
            address: 'lq1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
            isTestnet: false,
          ),
          selectedWallet: manual,
        ),
      );

      await cubit.continueOnAddressConfirmed();

      expect(cubit.state.selectedWallet?.id, manual.id);
      expect(cubit.state.error, 'This wallet cannot be used for sending.');
      verifyNever(
        () => harness.bestWallet.execute(
          wallets: any(named: 'wallets'),
          request: any(named: 'request'),
          amountSat: any(named: 'amountSat'),
        ),
      );
    },
  );

  test(
    'preselected external receive wallet blocks BIP21 prioritization fallback',
    () async {
      final harness = SendCubitHarness();
      final manual = sendCubitWallet(
        id: 'manual-wallet',
        label: 'Cold Storage',
      );
      final paymentPage = sendCubitWallet(
        id: 'payment-page',
        label: 'Payment Page-LBTC',
      );
      harness.stubWallets([manual, paymentPage]);
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: {
            paymentPage.id: ExternalReceiveWalletPurpose.paymentPage,
          },
        ),
      );

      final cubit = harness.createCubit(wallet: paymentPage);
      addTearDown(cubit.close);

      await cubit.loadWalletWithRatesAndFees();
      harness.seed(
        cubit,
        cubit.state.copyWith(
          paymentRequest: const PaymentRequest.bip21(
            network: Network.liquidMainnet,
            uri:
                'liquidnetwork:lq1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq'
                '?lightning=lnbc1invalid',
            address: 'lq1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq',
            lightning: 'lnbc1invalid',
          ),
          selectedWallet: manual,
        ),
      );

      await cubit.continueOnAddressConfirmed();

      expect(cubit.state.selectedWallet?.id, manual.id);
      expect(cubit.state.paymentRequest, isA<Bip21PaymentRequest>());
      expect(cubit.state.error, 'This wallet cannot be used for sending.');
      verifyNever(
        () => harness.bestWallet.execute(
          wallets: any(named: 'wallets'),
          request: any(named: 'request'),
          amountSat: any(named: 'amountSat'),
        ),
      );
    },
  );

  test('BTCPay Bitcoin wallet remains sendable', () async {
    final harness = SendCubitHarness();
    final manual = sendCubitWallet(id: 'manual-wallet', label: 'Cold Storage');
    final btcpayBitcoin = sendCubitWallet(
      id: 'btcpay-bitcoin',
      label: 'BTCPay-BTC',
      network: Network.bitcoinMainnet,
    );
    final btcpayLiquid = sendCubitWallet(
      id: 'btcpay-liquid',
      label: 'BTCPay-LBTC',
    );
    harness.stubWallets([manual, btcpayBitcoin, btcpayLiquid]);
    when(
      () => harness.externalReceiveWallets.idsForWallets(any()),
    ).thenAnswer(
      (_) async => ExternalReceiveWalletIds(
        purposeByWalletId: {
          btcpayBitcoin.id: ExternalReceiveWalletPurpose.btcpay,
          btcpayLiquid.id: ExternalReceiveWalletPurpose.btcpay,
        },
      ),
    );

    final cubit = harness.createCubit(wallet: btcpayBitcoin);
    addTearDown(cubit.close);

    await cubit.loadWalletWithRatesAndFees();

    expect(cubit.state.error, isNull);
    expect(cubit.state.wallets.map((wallet) => wallet.id), [
      manual.id,
      btcpayBitcoin.id,
    ]);
  });
}
