import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/swaps/domain/entity/swap.dart';
import 'package:bb_mobile/core/utils/payment_request.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/send/presentation/bloc/send_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'send_cubit_harness.dart';

void main() {
  setUpAll(registerSendCubitHarnessFallbacks);

  void stubSuccessfulDirectPayment(SendCubitHarness harness) {
    when(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
        walletId: any(named: 'walletId'),
      ),
    ).thenAnswer((_) async => 'lq1direct');
    when(
      () => harness.getNetworkFees.execute(isLiquid: any(named: 'isLiquid')),
    ).thenAnswer((_) async => sendCubitFeeOptions());
    when(
      () => harness.getWalletUtxos.execute(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async => []);
  }

  test(
    'does not attempt LUD-22 direct pay from Liquid testnet wallet',
    () async {
      final harness = SendCubitHarness();
      final wallet = sendCubitWallet(
        id: 'testnet-wallet',
        label: 'Instant Payments Testnet',
        network: Network.liquidTestnet,
        balanceSat: BigInt.from(100000),
      );
      when(
        () => harness.createSendSwap.execute(
          walletId: any(named: 'walletId'),
          type: any(named: 'type'),
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
        ),
      ).thenAnswer((_) async => sendCubitLnSendSwap(walletId: wallet.id));

      final cubit = harness.createCubit();
      addTearDown(cubit.close);
      harness.seed(
        cubit,
        SendState(
          step: SendStep.amount,
          sendType: SendType.lightning,
          paymentRequest: const PaymentRequest.lnAddress(
            address: 'alice@bullpay.ca',
          ),
          selectedWallet: wallet,
          amount: '1000',
          inputAmountCurrencyCode: BitcoinUnit.sats.code,
          selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
          selectedSwapFees: const SwapFees(),
        ),
      );

      await cubit.onAmountConfirmed();

      verifyNever(
        () => harness.tryLiquidDirectPay.execute(
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
          walletId: any(named: 'walletId'),
        ),
      );
      verify(
        () => harness.createSendSwap.execute(
          walletId: wallet.id,
          type: SwapType.liquidToLightning,
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
        ),
      ).called(1);
    },
  );

  test(
    'LUD-22 mainnet success builds Liquid payment only after confirm',
    () async {
      final harness = SendCubitHarness();
      final wallet = sendCubitWallet(
        id: 'mainnet-wallet',
        label: 'Instant Payments',
        network: Network.liquidMainnet,
        balanceSat: BigInt.from(100000),
      );
      stubSuccessfulDirectPayment(harness);
      when(
        () => harness.prepareLiquidSend.execute(
          walletId: any(named: 'walletId'),
          address: any(named: 'address'),
          networkFee: any(named: 'networkFee'),
          amountSat: any(named: 'amountSat'),
          drain: any(named: 'drain'),
        ),
      ).thenAnswer((_) async => 'pset');
      when(
        () => harness.calculateLiquidAbsoluteFees.execute(
          pset: any(named: 'pset'),
        ),
      ).thenAnswer((_) async => 10);

      final cubit = harness.createCubit();
      addTearDown(cubit.close);
      harness.seed(
        cubit,
        SendState(
          step: SendStep.amount,
          sendType: SendType.lightning,
          paymentRequest: const PaymentRequest.lnAddress(
            address: 'alice@bullpay.ca',
          ),
          selectedWallet: wallet,
          amount: '1000',
          inputAmountCurrencyCode: BitcoinUnit.sats.code,
          selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
          selectedSwapFees: const SwapFees(),
        ),
      );

      await cubit.onAmountConfirmed();

      verifyNever(
        () => harness.tryLiquidDirectPay.execute(
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
          walletId: any(named: 'walletId'),
        ),
      );
      expect(cubit.state.step, SendStep.confirm);

      await cubit.onConfirmTransactionClicked();

      verify(
        () => harness.tryLiquidDirectPay.execute(
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
          walletId: wallet.id,
        ),
      ).called(1);
      verifyNever(
        () => harness.createSendSwap.execute(
          walletId: any(named: 'walletId'),
          type: any(named: 'type'),
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
        ),
      );
      verify(
        () => harness.prepareLiquidSend.execute(
          walletId: wallet.id,
          address: 'lq1direct',
          networkFee: const NetworkFee.absolute(1),
          amountSat: 1000,
          drain: false,
        ),
      ).called(1);
      expect(cubit.state.amountConfirmedClicked, false);
      expect(cubit.state.buildTransactionException, isNull);
    },
  );

  test(
    'LUD-22 direct pay confirm bypasses Lightning swap fee balance check',
    () async {
      final harness = SendCubitHarness();
      final wallet = sendCubitWallet(
        id: 'mainnet-wallet',
        label: 'Instant Payments',
        network: Network.liquidMainnet,
        balanceSat: BigInt.from(1005),
      );
      stubSuccessfulDirectPayment(harness);
      when(
        () => harness.prepareLiquidSend.execute(
          walletId: any(named: 'walletId'),
          address: any(named: 'address'),
          networkFee: any(named: 'networkFee'),
          amountSat: any(named: 'amountSat'),
          drain: any(named: 'drain'),
        ),
      ).thenAnswer((_) async => 'pset');
      when(
        () => harness.calculateLiquidAbsoluteFees.execute(
          pset: any(named: 'pset'),
        ),
      ).thenAnswer((_) async => 1);

      final cubit = harness.createCubit();
      addTearDown(cubit.close);
      harness.seed(
        cubit,
        SendState(
          step: SendStep.amount,
          sendType: SendType.lightning,
          paymentRequest: const PaymentRequest.lnAddress(
            address: 'alice@bullpay.ca',
          ),
          selectedWallet: wallet,
          amount: '1000',
          inputAmountCurrencyCode: BitcoinUnit.sats.code,
          selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
          selectedSwapFees: const SwapFees(lockupFee: 100),
        ),
      );

      await cubit.onAmountConfirmed();

      verifyNever(
        () => harness.tryLiquidDirectPay.execute(
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
          walletId: any(named: 'walletId'),
        ),
      );
      verifyNever(
        () => harness.createSendSwap.execute(
          walletId: any(named: 'walletId'),
          type: any(named: 'type'),
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
        ),
      );
      expect(cubit.state.step, SendStep.confirm);
      expect(cubit.state.insufficientBalanceException, isNull);

      await cubit.onConfirmTransactionClicked();

      verify(
        () => harness.tryLiquidDirectPay.execute(
          lnAddress: 'alice@bullpay.ca',
          amountSat: 1000,
          walletId: wallet.id,
        ),
      ).called(1);
      verifyNever(
        () => harness.createSendSwap.execute(
          walletId: any(named: 'walletId'),
          type: any(named: 'type'),
          lnAddress: any(named: 'lnAddress'),
          amountSat: any(named: 'amountSat'),
        ),
      );
    },
  );

  test('LUD-22 direct pay is deferred below fallback swap minimum', () async {
    final harness = SendCubitHarness();
    final wallet = sendCubitWallet(
      id: 'mainnet-wallet',
      label: 'Instant Payments',
      network: Network.liquidMainnet,
      balanceSat: BigInt.from(100000),
    );
    stubSuccessfulDirectPayment(harness);
    when(
      () => harness.prepareLiquidSend.execute(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        amountSat: any(named: 'amountSat'),
        drain: any(named: 'drain'),
      ),
    ).thenAnswer((_) async => 'pset');
    when(
      () =>
          harness.calculateLiquidAbsoluteFees.execute(pset: any(named: 'pset')),
    ).thenAnswer((_) async => 1);

    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    harness.seed(
      cubit,
      SendState(
        step: SendStep.amount,
        sendType: SendType.lightning,
        paymentRequest: const PaymentRequest.lnAddress(
          address: 'alice@bullpay.ca',
        ),
        selectedWallet: wallet,
        amount: '50',
        inputAmountCurrencyCode: BitcoinUnit.sats.code,
        selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
        selectedSwapFees: const SwapFees(),
      ),
    );

    await cubit.onAmountConfirmed();

    verifyNever(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
        walletId: any(named: 'walletId'),
      ),
    );
    expect(cubit.state.step, SendStep.confirm);
    expect(cubit.state.swapLimitsException, isNull);

    await cubit.onConfirmTransactionClicked();

    verify(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: 'alice@bullpay.ca',
        amountSat: 50,
        walletId: wallet.id,
      ),
    ).called(1);
  });

  test('LUD-22 direct pay is deferred above fallback swap maximum', () async {
    final harness = SendCubitHarness();
    final wallet = sendCubitWallet(
      id: 'mainnet-wallet',
      label: 'Instant Payments',
      network: Network.liquidMainnet,
      balanceSat: BigInt.from(2000000),
    );
    stubSuccessfulDirectPayment(harness);
    when(
      () => harness.prepareLiquidSend.execute(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        amountSat: any(named: 'amountSat'),
        drain: any(named: 'drain'),
      ),
    ).thenAnswer((_) async => 'pset');
    when(
      () =>
          harness.calculateLiquidAbsoluteFees.execute(pset: any(named: 'pset')),
    ).thenAnswer((_) async => 1);

    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    harness.seed(
      cubit,
      SendState(
        step: SendStep.amount,
        sendType: SendType.lightning,
        paymentRequest: const PaymentRequest.lnAddress(
          address: 'alice@bullpay.ca',
        ),
        selectedWallet: wallet,
        amount: '1500',
        inputAmountCurrencyCode: BitcoinUnit.sats.code,
        selectedSwapLimits: const SwapLimits(min: 100, max: 1000),
        selectedSwapFees: const SwapFees(),
      ),
    );

    await cubit.onAmountConfirmed();

    verifyNever(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
        walletId: any(named: 'walletId'),
      ),
    );
    expect(cubit.state.step, SendStep.confirm);
    expect(cubit.state.swapLimitsException, isNull);

    await cubit.onConfirmTransactionClicked();

    verify(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: 'alice@bullpay.ca',
        amountSat: 1500,
        walletId: wallet.id,
      ),
    ).called(1);
  });

  test('LUD-22 direct pay build failure happens after confirm', () async {
    final harness = SendCubitHarness();
    final wallet = sendCubitWallet(
      id: 'mainnet-wallet',
      label: 'Instant Payments',
      network: Network.liquidMainnet,
      balanceSat: BigInt.from(100000),
    );
    stubSuccessfulDirectPayment(harness);
    when(
      () => harness.prepareLiquidSend.execute(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        amountSat: any(named: 'amountSat'),
        drain: any(named: 'drain'),
      ),
    ).thenThrow(Exception('build failed'));

    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    harness.seed(
      cubit,
      SendState(
        step: SendStep.amount,
        sendType: SendType.lightning,
        paymentRequest: const PaymentRequest.lnAddress(
          address: 'alice@bullpay.ca',
        ),
        selectedWallet: wallet,
        amount: '1000',
        inputAmountCurrencyCode: BitcoinUnit.sats.code,
        selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
        selectedSwapFees: const SwapFees(),
      ),
    );

    await cubit.onAmountConfirmed();

    verifyNever(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
        walletId: any(named: 'walletId'),
      ),
    );
    expect(cubit.state.step, SendStep.confirm);

    await cubit.onConfirmTransactionClicked();

    verify(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: 'alice@bullpay.ca',
        amountSat: 1000,
        walletId: wallet.id,
      ),
    ).called(1);
    expect(cubit.state.step, SendStep.confirm);
    expect(cubit.state.amountConfirmedClicked, false);
    expect(cubit.state.sendType, SendType.lightning);
    expect(cubit.state.paymentRequestAddress, 'alice@bullpay.ca');
    expect(cubit.state.lud22OriginalAddress, isNull);
    expect(cubit.state.buildTransactionException, isNotNull);
  });

  test('LUD-22 direct pay is skipped for send max', () async {
    final harness = SendCubitHarness();
    final wallet = sendCubitWallet(
      id: 'mainnet-wallet',
      label: 'Instant Payments',
      network: Network.liquidMainnet,
      balanceSat: BigInt.from(100000),
    );
    when(
      () => harness.createSendSwap.execute(
        walletId: any(named: 'walletId'),
        type: any(named: 'type'),
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
      ),
    ).thenAnswer((_) async => sendCubitLnSendSwap(walletId: wallet.id));

    final cubit = harness.createCubit();
    addTearDown(cubit.close);
    harness.seed(
      cubit,
      SendState(
        step: SendStep.amount,
        sendType: SendType.lightning,
        paymentRequest: const PaymentRequest.lnAddress(
          address: 'alice@bullpay.ca',
        ),
        selectedWallet: wallet,
        amount: '1000',
        inputAmountCurrencyCode: BitcoinUnit.sats.code,
        selectedSwapLimits: const SwapLimits(min: 100, max: 1000000),
        selectedSwapFees: const SwapFees(),
        sendMax: true,
      ),
    );

    await cubit.onAmountConfirmed();

    verifyNever(
      () => harness.tryLiquidDirectPay.execute(
        lnAddress: any(named: 'lnAddress'),
        amountSat: any(named: 'amountSat'),
        walletId: any(named: 'walletId'),
      ),
    );
    verify(
      () => harness.createSendSwap.execute(
        walletId: wallet.id,
        type: SwapType.liquidToLightning,
        lnAddress: 'alice@bullpay.ca',
        amountSat: 1000,
      ),
    ).called(1);
  });
}
