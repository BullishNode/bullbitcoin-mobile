import 'dart:async';

import 'package:bb_mobile/core/ark/usecases/check_ark_wallet_setup_usecase.dart';
import 'package:bb_mobile/core/ark/usecases/get_ark_wallet_usecase.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/datasources/seed_store_type_datasource.dart';
import 'package:bb_mobile/core/swaps/domain/entity/auto_swap.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/auto_swap_execution_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/disable_autoswap_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/disable_autoswap_warning_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/restart_swap_watcher_usecase.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/save_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/init_tor_usecase.dart';
import 'package:bb_mobile/core/tor/data/usecases/is_tor_required_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/check_wallet_syncing_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/check_backup_needed_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/delete_wallet_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_electrum_sync_results_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_finished_wallet_syncs_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/watch_started_wallet_syncs_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/wallet/domain/usecase/get_unconfirmed_incoming_balance_usecase.dart';
import 'package:bb_mobile/features/wallet/presentation/bloc/wallet_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWalletsUsecase extends Mock implements GetWalletsUsecase {}

class _MockCheckWalletSyncingUsecase extends Mock
    implements CheckWalletSyncingUsecase {}

class _MockCheckBackupNeededUsecase extends Mock
    implements CheckBackupNeededUsecase {}

class _MockWatchStartedWalletSyncsUsecase extends Mock
    implements WatchStartedWalletSyncsUsecase {}

class _MockWatchFinishedWalletSyncsUsecase extends Mock
    implements WatchFinishedWalletSyncsUsecase {}

class _MockWatchElectrumSyncResultsUsecase extends Mock
    implements WatchElectrumSyncResultsUsecase {}

class _MockRestartSwapWatcherUsecase extends Mock
    implements RestartSwapWatcherUsecase {}

class _MockInitTorUsecase extends Mock implements InitTorUsecase {}

class _MockIsTorRequiredUsecase extends Mock implements IsTorRequiredUsecase {}

class _MockGetUnconfirmedIncomingBalanceUsecase extends Mock
    implements GetUnconfirmedIncomingBalanceUsecase {}

class _MockGetAutoSwapSettingsUsecase extends Mock
    implements GetAutoSwapSettingsUsecase {}

class _MockSaveAutoSwapSettingsUsecase extends Mock
    implements SaveAutoSwapSettingsUsecase {}

class _MockDisableAutoswapWarningUsecase extends Mock
    implements DisableAutoswapWarningUsecase {}

class _MockDisableAutoswapUsecase extends Mock
    implements DisableAutoswapUsecase {}

class _MockAutoSwapExecutionUsecase extends Mock
    implements AutoSwapExecutionUsecase {}

class _MockDeleteWalletUsecase extends Mock implements DeleteWalletUsecase {}

class _MockGetArkWalletUsecase extends Mock implements GetArkWalletUsecase {}

class _MockCheckArkWalletSetupUsecase extends Mock
    implements CheckArkWalletSetupUsecase {}

class _MockSeedStoreTypeDatasource extends Mock
    implements SeedStoreTypeDatasource {}

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  setUpAll(() {
    registerFallbackValue(ExternalReceiveWalletPurpose.paymentPage);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      ),
    );
  });

  test('does not block deletion when classification fails', () async {
    final harness = _Harness();
    final wallet = _wallet(id: 'external-wallet', label: 'Payment Page-LBTC');
    harness.stubWallets([wallet]);
    when(
      () => harness.externalReceiveWallets.idsForWallets(any()),
    ).thenThrow(Exception('origin unavailable'));
    when(
      () => harness.deleteWallet.execute(walletId: wallet.id),
    ).thenAnswer((_) async {});

    final bloc = harness.createBloc();
    addTearDown(bloc.close);

    bloc.add(const WalletStarted());
    await expectLater(
      bloc.stream,
      emitsThrough(
        predicate<WalletState>((state) => state.status == WalletStatus.success),
      ),
    );

    bloc.add(WalletDeleted(wallet.id));
    await expectLater(
      bloc.stream,
      emitsThrough(
        predicate<WalletState>(
          (state) => state.wallets.every((w) => w.id != wallet.id),
        ),
      ),
    );

    verify(() => harness.deleteWallet.execute(walletId: wallet.id)).called(1);
  });

  test(
    'allows ordinary non-default deletion after classification succeeds',
    () async {
      final harness = _Harness();
      final wallet = _wallet(id: 'manual-wallet', label: 'Cold Storage');
      harness.stubWallets([wallet]);
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer((_) async => ExternalReceiveWalletIds.empty);
      when(
        () => harness.deleteWallet.execute(walletId: wallet.id),
      ).thenAnswer((_) async {});

      final bloc = harness.createBloc();
      addTearDown(bloc.close);

      bloc.add(const WalletStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) => state.status == WalletStatus.success,
          ),
        ),
      );

      bloc.add(WalletDeleted(wallet.id));
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) => state.wallets.every((w) => w.id != wallet.id),
          ),
        ),
      );

      verify(() => harness.deleteWallet.execute(walletId: wallet.id)).called(1);
    },
  );

  test(
    'reclassifies external receive visibility without reloading wallets',
    () async {
      final harness = _Harness();
      final wallet = _wallet(id: 'payment-page', label: 'Payment Page-LBTC');
      harness.stubWallets([wallet]);
      var hidden = false;
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: {
            wallet.id: ExternalReceiveWalletPurpose.paymentPage,
          },
          hiddenOnHomeWalletIds: hidden ? {wallet.id} : {},
        ),
      );

      final bloc = harness.createBloc();
      addTearDown(bloc.close);

      bloc.add(const WalletStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) =>
                state.status == WalletStatus.success &&
                !state.externalReceiveWalletIds.isHiddenOnHome(wallet.id),
          ),
        ),
      );
      await untilCalled(() => harness.getWallets.execute(sync: true));
      clearInteractions(harness.getWallets);

      hidden = true;
      bloc.add(const WalletExternalReceiveSettingsChanged());

      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) => state.externalReceiveWalletIds.isHiddenOnHome(wallet.id),
          ),
        ),
      );
      verifyNever(() => harness.getWallets.execute());
      verifyNever(() => harness.getWallets.execute(sync: true));
    },
  );

  test(
    'reloads wallets after external receive wallets are created without syncing',
    () async {
      final harness = _Harness();
      final defaultLiquid = _wallet(
        id: 'default-liquid',
        label: 'Instant Payments',
        isDefault: true,
      );
      final paymentPage = _wallet(
        id: 'payment-page',
        label: 'Payment Page-LBTC',
      );
      var walletReadCount = 0;
      when(() => harness.getWallets.execute()).thenAnswer((_) async {
        walletReadCount += 1;
        return walletReadCount == 1
            ? [defaultLiquid]
            : [defaultLiquid, paymentPage];
      });
      when(
        () => harness.getWallets.execute(sync: true),
      ).thenAnswer((_) async => [defaultLiquid]);
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: walletReadCount == 1
              ? {}
              : {paymentPage.id: ExternalReceiveWalletPurpose.paymentPage},
        ),
      );
      when(
        () => harness.getUnconfirmedIncomingBalance.execute(
          walletIds: any(named: 'walletIds'),
        ),
      ).thenAnswer((_) async => 0);

      final bloc = harness.createBloc();
      addTearDown(bloc.close);

      bloc.add(const WalletStarted());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) =>
                state.status == WalletStatus.success &&
                state.wallets.length == 1,
          ),
        ),
      );
      clearInteractions(harness.getWallets);

      bloc.add(const WalletListChanged());
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) =>
                state.wallets.any((wallet) => wallet.id == paymentPage.id) &&
                state.externalReceiveWalletIds.isExternalReceiveWallet(
                  paymentPage.id,
                ),
          ),
        ),
      );

      verify(() => harness.getWallets.execute()).called(1);
      verifyNever(() => harness.getWallets.execute(sync: true));
    },
  );

  test(
    'sweeps a Liquid external receive wallet after that wallet syncs',
    () async {
      final harness = _Harness();
      final defaultLiquid = _wallet(
        id: 'default-liquid',
        label: 'Instant Payments',
        isDefault: true,
      );
      final paymentPage = _wallet(
        id: 'payment-page',
        label: 'Payment Page-LBTC',
        balanceSat: 1000,
      );
      final paymentPageAfterSweep = paymentPage.copyWith(
        balanceSat: BigInt.zero,
      );
      var syncedReadCount = 0;
      when(
        () => harness.getWallets.execute(),
      ).thenAnswer((_) async => [defaultLiquid, paymentPage]);
      when(() => harness.getWallets.execute(sync: true)).thenAnswer((_) async {
        syncedReadCount += 1;
        if (syncedReadCount >= 2) {
          return [defaultLiquid, paymentPageAfterSweep];
        }
        return [defaultLiquid, paymentPage];
      });
      final accountKey = ExternalReceiveWalletPurpose.paymentPage
          .liquidAccountKey(isTestnet: false);
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: {
            paymentPage.id: ExternalReceiveWalletPurpose.paymentPage,
          },
          accountKeyByWalletId: {paymentPage.id: accountKey},
        ),
      );
      when(
        () => harness.getUnconfirmedIncomingBalance.execute(
          walletIds: any(named: 'walletIds'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => harness.externalReceiveWallets.shouldAutoSweepForAccount(
          accountKey,
        ),
      ).thenAnswer((_) async => true);
      when(
        () => harness.externalReceiveWallets.sweep(
          isTestnet: false,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          expectedWalletId: paymentPage.id,
          accountKey: accountKey,
        ),
      ).thenAnswer((_) async => 'txid');
      when(
        () => harness.getAutoSwapSettings.execute(),
      ).thenAnswer((_) async => const AutoSwap(enabled: false));

      final bloc = harness.createBloc();
      addTearDown(bloc.close);

      bloc.add(const WalletStarted());
      await untilCalled(() => harness.getWallets.execute(sync: true));
      clearInteractions(harness.getWallets);

      bloc.add(WalletSyncFinished(paymentPage));
      await untilCalled(
        () => harness.externalReceiveWallets.sweep(
          isTestnet: false,
          purpose: ExternalReceiveWalletPurpose.paymentPage,
          expectedWalletId: paymentPage.id,
          accountKey: accountKey,
        ),
      );

      verify(
        () => harness.externalReceiveWallets.shouldAutoSweepForAccount(
          accountKey,
        ),
      ).called(1);
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) =>
                state.wallets
                    .firstWhere((wallet) => wallet.id == paymentPage.id)
                    .balanceSat ==
                BigInt.zero,
          ),
        ),
      );
      verify(() => harness.getWallets.execute(sync: true)).called(1);
    },
  );

  test(
    'sweeps a Bitcoin external receive wallet after that wallet syncs',
    () async {
      final harness = _Harness();
      final defaultBitcoin = _wallet(
        id: 'default-bitcoin',
        label: 'Secure Bitcoin',
        isDefault: true,
        network: Network.bitcoinMainnet,
      );
      final btcpayBitcoin = _wallet(
        id: 'btcpay-bitcoin',
        label: 'BTCPay-BTC',
        balanceSat: 10000,
        network: Network.bitcoinMainnet,
      );
      final btcpayBitcoinAfterSweep = btcpayBitcoin.copyWith(
        balanceSat: BigInt.zero,
      );
      var syncedReadCount = 0;
      when(
        () => harness.getWallets.execute(),
      ).thenAnswer((_) async => [defaultBitcoin, btcpayBitcoin]);
      when(() => harness.getWallets.execute(sync: true)).thenAnswer((_) async {
        syncedReadCount += 1;
        if (syncedReadCount >= 2) {
          return [defaultBitcoin, btcpayBitcoinAfterSweep];
        }
        return [defaultBitcoin, btcpayBitcoin];
      });
      final accountKey = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      );
      when(
        () => harness.externalReceiveWallets.idsForWallets(any()),
      ).thenAnswer(
        (_) async => ExternalReceiveWalletIds(
          purposeByWalletId: {
            btcpayBitcoin.id: ExternalReceiveWalletPurpose.btcpay,
          },
          accountKeyByWalletId: {btcpayBitcoin.id: accountKey},
        ),
      );
      when(
        () => harness.getUnconfirmedIncomingBalance.execute(
          walletIds: any(named: 'walletIds'),
        ),
      ).thenAnswer((_) async => 0);
      when(
        () => harness.externalReceiveWallets.shouldAutoSweepForAccount(
          accountKey,
        ),
      ).thenAnswer((_) async => true);
      when(
        () => harness.externalReceiveWallets.sweep(
          isTestnet: false,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          expectedWalletId: btcpayBitcoin.id,
          accountKey: accountKey,
        ),
      ).thenAnswer((_) async => 'bitcoin-txid');

      final bloc = harness.createBloc();
      addTearDown(bloc.close);

      bloc.add(const WalletStarted());
      await untilCalled(() => harness.getWallets.execute(sync: true));
      clearInteractions(harness.getWallets);

      bloc.add(WalletSyncFinished(btcpayBitcoin));
      await untilCalled(
        () => harness.externalReceiveWallets.sweep(
          isTestnet: false,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          expectedWalletId: btcpayBitcoin.id,
          accountKey: accountKey,
        ),
      );

      verify(
        () => harness.externalReceiveWallets.shouldAutoSweepForAccount(
          accountKey,
        ),
      ).called(1);
      await expectLater(
        bloc.stream,
        emitsThrough(
          predicate<WalletState>(
            (state) =>
                state.wallets
                    .firstWhere((wallet) => wallet.id == btcpayBitcoin.id)
                    .balanceSat ==
                BigInt.zero,
          ),
        ),
      );
      verify(() => harness.getWallets.execute(sync: true)).called(1);
    },
  );

  test('does not ask autosweep settings for ordinary synced wallets', () async {
    final harness = _Harness();
    final wallet = _wallet(
      id: 'manual-bitcoin',
      label: 'Savings',
      network: Network.bitcoinMainnet,
    );
    harness.stubWallets([wallet]);
    when(
      () => harness.externalReceiveWallets.idsForWallets(any()),
    ).thenAnswer((_) async => ExternalReceiveWalletIds.empty);
    when(
      () => harness.getUnconfirmedIncomingBalance.execute(
        walletIds: any(named: 'walletIds'),
      ),
    ).thenAnswer((_) async => 0);

    final bloc = harness.createBloc();
    addTearDown(bloc.close);

    bloc.add(const WalletStarted());
    await expectLater(
      bloc.stream,
      emitsThrough(
        predicate<WalletState>((state) => state.status == WalletStatus.success),
      ),
    );

    bloc.add(WalletSyncFinished(wallet));
    await untilCalled(
      () => harness.getUnconfirmedIncomingBalance.execute(
        walletIds: any(named: 'walletIds'),
      ),
    );

    verifyNever(
      () => harness.externalReceiveWallets.shouldAutoSweepForAccount(any()),
    );
    verifyNever(
      () => harness.externalReceiveWallets.sweep(
        isTestnet: any(named: 'isTestnet'),
        purpose: any(named: 'purpose'),
        expectedWalletId: any(named: 'expectedWalletId'),
        accountKey: any(named: 'accountKey'),
      ),
    );
  });
}

class _Harness {
  final getWallets = _MockGetWalletsUsecase();
  final checkWalletSyncing = _MockCheckWalletSyncingUsecase();
  final checkBackupNeeded = _MockCheckBackupNeededUsecase();
  final watchStartedSyncs = _MockWatchStartedWalletSyncsUsecase();
  final watchFinishedSyncs = _MockWatchFinishedWalletSyncsUsecase();
  final watchElectrumSyncResults = _MockWatchElectrumSyncResultsUsecase();
  final restartSwapWatcher = _MockRestartSwapWatcherUsecase();
  final initializeTor = _MockInitTorUsecase();
  final isTorRequired = _MockIsTorRequiredUsecase();
  final getUnconfirmedIncomingBalance =
      _MockGetUnconfirmedIncomingBalanceUsecase();
  final getAutoSwapSettings = _MockGetAutoSwapSettingsUsecase();
  final saveAutoSwapSettings = _MockSaveAutoSwapSettingsUsecase();
  final disableAutoswapWarning = _MockDisableAutoswapWarningUsecase();
  final disableAutoswap = _MockDisableAutoswapUsecase();
  final autoSwapExecution = _MockAutoSwapExecutionUsecase();
  final deleteWallet = _MockDeleteWalletUsecase();
  final getArkWallet = _MockGetArkWalletUsecase();
  final checkArkWalletSetup = _MockCheckArkWalletSetupUsecase();
  final seedStoreType = _MockSeedStoreTypeDatasource();
  final externalReceiveWallets = _MockExternalReceiveWalletsFacade();

  _Harness() {
    when(() => checkWalletSyncing.execute()).thenReturn(false);
    when(() => checkBackupNeeded.execute()).thenAnswer((_) async => false);
    when(() => watchStartedSyncs.execute()).thenAnswer((_) => Stream.empty());
    when(() => watchFinishedSyncs.execute()).thenAnswer((_) => Stream.empty());
    when(
      () => watchElectrumSyncResults.execute(),
    ).thenAnswer((_) => Stream.empty());
    when(() => seedStoreType.read()).thenAnswer((_) async => null);
    when(() => checkArkWalletSetup.execute()).thenAnswer((_) async => false);
    when(() => restartSwapWatcher.execute()).thenAnswer((_) async {});
  }

  void stubWallets(List<Wallet> wallets) {
    when(() => getWallets.execute()).thenAnswer((_) async => wallets);
    when(() => getWallets.execute(sync: true)).thenAnswer((_) async => wallets);
  }

  WalletBloc createBloc() {
    return WalletBloc(
      getWalletsUsecase: getWallets,
      checkWalletSyncingUsecase: checkWalletSyncing,
      checkBackupNeededUsecase: checkBackupNeeded,
      watchStartedWalletSyncsUsecase: watchStartedSyncs,
      watchFinishedWalletSyncsUsecase: watchFinishedSyncs,
      watchElectrumSyncResultsUsecase: watchElectrumSyncResults,
      restartSwapWatcherUsecase: restartSwapWatcher,
      initializeTorUsecase: initializeTor,
      checkForTorInitializationOnStartupUsecase: isTorRequired,
      getUnconfirmedIncomingBalanceUsecase: getUnconfirmedIncomingBalance,
      getAutoSwapSettingsUsecase: getAutoSwapSettings,
      saveAutoSwapSettingsUsecase: saveAutoSwapSettings,
      disableAutoswapWarningUsecase: disableAutoswapWarning,
      disableAutoswapUsecase: disableAutoswap,
      autoSwapExecutionUsecase: autoSwapExecution,
      deleteWalletUsecase: deleteWallet,
      getArkWalletUsecase: getArkWallet,
      checkArkWalletSetupUsecase: checkArkWalletSetup,
      seedStoreTypeDatasource: seedStoreType,
      externalReceiveWalletsFacade: externalReceiveWallets,
    );
  }
}

Wallet _wallet({
  required String id,
  required String label,
  bool isDefault = false,
  int balanceSat = 0,
  Network network = Network.liquidMainnet,
}) {
  return Wallet(
    origin: id,
    label: label,
    network: network,
    isDefault: isDefault,
    xpubFingerprint: '',
    scriptType: ScriptType.bip84,
    xpub: '',
    externalPublicDescriptor: '',
    internalPublicDescriptor: '',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.from(balanceSat),
  );
}
