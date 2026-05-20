import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/convert_sats_to_currency_amount_usecase.dart';
import 'package:bb_mobile/core/exchange/domain/usecases/get_available_currencies_usecase.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/payjoin/domain/usecases/send_with_payjoin_usecase.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/create_chain_swap_to_external_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/decode_invoice_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_swap_limits_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/update_send_swap_lockup_fees_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/verify_chain_swap_amount_send_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/watch_swap_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_utxos_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_finished_wallet_syncs_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_wallet_transaction_by_tx_id_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_bitcoin_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/calculate_liquid_absolute_fees_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/create_send_swap_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/detect_bitcoin_string_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_bitcoin_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/prepare_liquid_send_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/select_best_wallet_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_bitcoin_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/sign_liquid_tx_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/try_liquid_direct_pay_usecase.dart';
import 'package:bb_mobile/features/send/domain/usecases/update_paid_send_swap_usecase.dart';
import 'package:bb_mobile/features/send/presentation/bloc/send_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockLabelsFacade extends Mock implements LabelsFacade {}

class _MockSelectBestWalletUsecase extends Mock
    implements SelectBestWalletUsecase {}

class _MockDetectBitcoinStringUsecase extends Mock
    implements DetectBitcoinStringUsecase {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockConvertSatsToCurrencyAmountUsecase extends Mock
    implements ConvertSatsToCurrencyAmountUsecase {}

class _MockGetNetworkFeesUsecase extends Mock
    implements GetNetworkFeesUsecase {}

class _MockGetWalletUtxosUsecase extends Mock
    implements GetWalletUtxosUsecase {}

class _MockGetAvailableCurrenciesUsecase extends Mock
    implements GetAvailableCurrenciesUsecase {}

class _MockPrepareBitcoinSendUsecase extends Mock
    implements PrepareBitcoinSendUsecase {}

class _MockPrepareLiquidSendUsecase extends Mock
    implements PrepareLiquidSendUsecase {}

class _MockSendWithPayjoinUsecase extends Mock
    implements SendWithPayjoinUsecase {}

class _MockGetWalletsUsecase extends Mock implements GetWalletsUsecase {}

class _MockGetWalletUsecase extends Mock implements GetWalletUsecase {}

class _MockCreateSendSwapUsecase extends Mock
    implements CreateSendSwapUsecase {}

class _MockUpdatePaidSendSwapUsecase extends Mock
    implements UpdatePaidSendSwapUsecase {}

class _MockGetSwapLimitsUsecase extends Mock implements GetSwapLimitsUsecase {}

class _MockWatchSwapUsecase extends Mock implements WatchSwapUsecase {}

class _MockWatchFinishedWalletSyncsUsecase extends Mock
    implements WatchFinishedWalletSyncsUsecase {}

class _MockDecodeInvoiceUsecase extends Mock implements DecodeInvoiceUsecase {}

class _MockSignBitcoinTxUsecase extends Mock implements SignBitcoinTxUsecase {}

class _MockSignLiquidTxUsecase extends Mock implements SignLiquidTxUsecase {}

class _MockBroadcastBitcoinTransactionUsecase extends Mock
    implements BroadcastBitcoinTransactionUsecase {}

class _MockBroadcastLiquidTransactionUsecase extends Mock
    implements BroadcastLiquidTransactionUsecase {}

class _MockCalculateLiquidAbsoluteFeesUsecase extends Mock
    implements CalculateLiquidAbsoluteFeesUsecase {}

class _MockCreateChainSwapToExternalUsecase extends Mock
    implements CreateChainSwapToExternalUsecase {}

class _MockWatchWalletTransactionByTxIdUsecase extends Mock
    implements WatchWalletTransactionByTxIdUsecase {}

class _MockCalculateBitcoinAbsoluteFeesUsecase extends Mock
    implements CalculateBitcoinAbsoluteFeesUsecase {}

class _MockUpdateSendSwapLockupFeesUsecase extends Mock
    implements UpdateSendSwapLockupFeesUsecase {}

class _MockVerifyChainSwapAmountSendUsecase extends Mock
    implements VerifyChainSwapAmountSendUsecase {}

class _MockTryLiquidDirectPayUsecase extends Mock
    implements TryLiquidDirectPayUsecase {}

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  test('first classification failure does not load sendable wallets', () async {
    final harness = _Harness();
    final manual = _wallet(id: 'manual-wallet', label: 'Cold Storage');
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
      final harness = _Harness();
      final manual = _wallet(id: 'manual-wallet', label: 'Cold Storage');
      final lightningAddress = _wallet(
        id: 'lightning-address',
        label: 'Lightning Address-LBTC',
      );
      final paymentPage = _wallet(
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

class _Harness {
  final labels = _MockLabelsFacade();
  final bestWallet = _MockSelectBestWalletUsecase();
  final detectBitcoinString = _MockDetectBitcoinStringUsecase();
  final getSettings = _MockGetSettingsUsecase();
  final convertSatsToCurrency = _MockConvertSatsToCurrencyAmountUsecase();
  final getNetworkFees = _MockGetNetworkFeesUsecase();
  final getWalletUtxos = _MockGetWalletUtxosUsecase();
  final getAvailableCurrencies = _MockGetAvailableCurrenciesUsecase();
  final prepareBitcoinSend = _MockPrepareBitcoinSendUsecase();
  final prepareLiquidSend = _MockPrepareLiquidSendUsecase();
  final sendWithPayjoin = _MockSendWithPayjoinUsecase();
  final getWallets = _MockGetWalletsUsecase();
  final getWallet = _MockGetWalletUsecase();
  final createSendSwap = _MockCreateSendSwapUsecase();
  final updatePaidSendSwap = _MockUpdatePaidSendSwapUsecase();
  final getSwapLimits = _MockGetSwapLimitsUsecase();
  final watchSwap = _MockWatchSwapUsecase();
  final watchFinishedWalletSyncs = _MockWatchFinishedWalletSyncsUsecase();
  final decodeInvoice = _MockDecodeInvoiceUsecase();
  final signBitcoinTx = _MockSignBitcoinTxUsecase();
  final signLiquidTx = _MockSignLiquidTxUsecase();
  final broadcastBitcoinTx = _MockBroadcastBitcoinTransactionUsecase();
  final broadcastLiquidTx = _MockBroadcastLiquidTransactionUsecase();
  final calculateLiquidAbsoluteFees = _MockCalculateLiquidAbsoluteFeesUsecase();
  final createChainSwapToExternal = _MockCreateChainSwapToExternalUsecase();
  final watchWalletTransactionByTxId =
      _MockWatchWalletTransactionByTxIdUsecase();
  final calculateBitcoinAbsoluteFees =
      _MockCalculateBitcoinAbsoluteFeesUsecase();
  final updateSendSwapLockupFees = _MockUpdateSendSwapLockupFeesUsecase();
  final verifyChainSwapAmountSend = _MockVerifyChainSwapAmountSendUsecase();
  final tryLiquidDirectPay = _MockTryLiquidDirectPayUsecase();
  final externalReceiveWallets = _MockExternalReceiveWalletsFacade();

  _Harness() {
    when(() => getSettings.execute()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'USD',
      ),
    );
    when(() => convertSatsToCurrency.execute()).thenAnswer((_) async => 1);
    when(
      () => convertSatsToCurrency.execute(
        currencyCode: any(named: 'currencyCode'),
      ),
    ).thenAnswer((_) async => 1);
    when(
      () => getAvailableCurrencies.execute(),
    ).thenAnswer((_) async => ['USD']);
  }

  void stubWallets(List<Wallet> wallets) {
    when(() => getWallets.execute()).thenAnswer((_) async => wallets);
  }

  SendCubit createCubit() {
    return SendCubit(
      labelsFacade: labels,
      bestWalletUsecase: bestWallet,
      detectBitcoinStringUsecase: detectBitcoinString,
      getSettingsUsecase: getSettings,
      convertSatsToCurrencyAmountUsecase: convertSatsToCurrency,
      getNetworkFeesUsecase: getNetworkFees,
      getWalletUtxosUsecase: getWalletUtxos,
      getAvailableCurrenciesUsecase: getAvailableCurrencies,
      prepareBitcoinSendUsecase: prepareBitcoinSend,
      prepareLiquidSendUsecase: prepareLiquidSend,
      sendWithPayjoinUsecase: sendWithPayjoin,
      getWalletsUsecase: getWallets,
      getWalletUsecase: getWallet,
      createSendSwapUsecase: createSendSwap,
      updatePaidSendSwapUsecase: updatePaidSendSwap,
      getSwapLimitsUsecase: getSwapLimits,
      watchSwapUsecase: watchSwap,
      watchFinishedWalletSyncsUsecase: watchFinishedWalletSyncs,
      decodeInvoiceUsecase: decodeInvoice,
      signBitcoinTxUsecase: signBitcoinTx,
      signLiquidTxUsecase: signLiquidTx,
      broadcastBitcoinTxUsecase: broadcastBitcoinTx,
      broadcastLiquidTxUsecase: broadcastLiquidTx,
      calculateLiquidAbsoluteFeesUsecase: calculateLiquidAbsoluteFees,
      createChainSwapToExternalUsecase: createChainSwapToExternal,
      watchWalletTransactionByTxIdUsecase: watchWalletTransactionByTxId,
      calculateBitcoinAbsoluteFeesUsecase: calculateBitcoinAbsoluteFees,
      updateSendSwapLockupFeesUsecase: updateSendSwapLockupFees,
      verifyChainSwapAmountSendUsecase: verifyChainSwapAmountSend,
      tryLiquidDirectPayUsecase: tryLiquidDirectPay,
      externalReceiveWalletsFacade: externalReceiveWallets,
    );
  }
}

Wallet _wallet({required String id, required String label}) {
  return Wallet(
    origin: id,
    label: label,
    network: Network.liquidMainnet,
    xpubFingerprint: '',
    scriptType: ScriptType.bip84,
    xpub: '',
    externalPublicDescriptor: '',
    internalPublicDescriptor: '',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
