import 'dart:async';

import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/presentation/get_paid_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockExternalReceiveWalletsFacade extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  late _MockGetSettingsUsecase getSettings;
  late _MockExternalReceiveWalletsFacade externalReceiveWallets;
  late GetPaidSettingsCubit cubit;

  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
    );
  });

  setUp(() {
    getSettings = _MockGetSettingsUsecase();
    externalReceiveWallets = _MockExternalReceiveWalletsFacade();
    cubit = GetPaidSettingsCubit(
      getSettings: getSettings,
      externalReceiveWallets: externalReceiveWallets,
    );
    when(() => getSettings.execute()).thenAnswer((_) async => _settings());
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
  });

  test('does not restore wallets until explicitly requested', () {
    expect(cubit.state.isRestoringWallets, isFalse);
    expect(cubit.state.restoreOutcomes, isNull);
    verifyNever(() => getSettings.execute());
    verifyNever(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: any(named: 'environment'),
      ),
    );
  });

  test('loads Lightning Address wallet settings', () async {
    when(
      () => externalReceiveWallets.shouldAutoSweepForAccount(any()),
    ).thenAnswer((_) async => true);
    when(
      () => externalReceiveWallets.isHiddenOnHomeForAccount(any()),
    ).thenAnswer((_) async => true);
    when(
      () => externalReceiveWallets.shouldAutoSweepForAccount(
        ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
          isTestnet: false,
        ),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => externalReceiveWallets.isHiddenOnHomeForAccount(
        ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
      ),
    ).thenAnswer((_) async => false);
    when(
      () => externalReceiveWallets.shouldAutoSweepForAccount(
        ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: false),
      ),
    ).thenAnswer((_) async => false);

    await cubit.load();

    expect(cubit.state.isLoadingSettings, isFalse);
    expect(cubit.state.lightningAddressAutoSweep, isFalse);
    expect(cubit.state.lightningAddressHideWallet, isTrue);
    expect(cubit.state.paymentPageAutoSweep, isTrue);
    expect(cubit.state.btcpayLiquidHideWallet, isTrue);
    expect(cubit.state.btcpayBitcoinAutoSweep, isFalse);
    expect(cubit.state.btcpayBitcoinHideWallet, isFalse);
    expect(cubit.state.loadFailed, isFalse);
    expect(cubit.state.saveFailed, isFalse);
  });

  test('loads settings with testnet account keys on testnet', () async {
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) async => _settings(environment: Environment.testnet));
    when(
      () => externalReceiveWallets.shouldAutoSweepForAccount(any()),
    ).thenAnswer((_) async => true);
    when(
      () => externalReceiveWallets.isHiddenOnHomeForAccount(any()),
    ).thenAnswer((_) async => true);

    await cubit.load();

    verify(
      () => externalReceiveWallets.shouldAutoSweepForAccount(
        ExternalReceiveWalletPurpose.lightningAddress.liquidAccountKey(
          isTestnet: true,
        ),
      ),
    ).called(1);
    verify(
      () => externalReceiveWallets.isHiddenOnHomeForAccount(
        ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
          isTestnet: true,
        ),
      ),
    ).called(1);
    verify(
      () => externalReceiveWallets.shouldAutoSweepForAccount(
        ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(isTestnet: true),
      ),
    ).called(1);
  });

  test('updates Lightning Address wallet settings', () async {
    final lightningAddress = ExternalReceiveWalletPurpose.lightningAddress
        .liquidAccountKey(isTestnet: false);
    when(
      () => externalReceiveWallets.setAutoSweepForAccount(
        lightningAddress,
        false,
      ),
    ).thenAnswer((_) async {});
    when(
      () => externalReceiveWallets.setHiddenOnHomeForAccount(
        lightningAddress,
        false,
      ),
    ).thenAnswer((_) async {});

    await cubit.setLightningAddressAutoSweep(false);
    await cubit.setLightningAddressHideWallet(false);

    expect(cubit.state.lightningAddressAutoSweep, isFalse);
    expect(cubit.state.lightningAddressHideWallet, isFalse);
    expect(cubit.state.isSavingSettings, isFalse);
    verify(
      () => externalReceiveWallets.setAutoSweepForAccount(
        lightningAddress,
        false,
      ),
    ).called(1);
    verify(
      () => externalReceiveWallets.setHiddenOnHomeForAccount(
        lightningAddress,
        false,
      ),
    ).called(1);
  });

  test('updates Payment Page and BTCPay wallet settings', () async {
    final paymentPage = ExternalReceiveWalletPurpose.paymentPage
        .liquidAccountKey(isTestnet: false);
    final btcpayLiquid = ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
      isTestnet: false,
    );
    final btcpayBitcoin = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
      isTestnet: false,
    );
    when(
      () => externalReceiveWallets.setAutoSweepForAccount(paymentPage, false),
    ).thenAnswer((_) async {});
    when(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayLiquid, false),
    ).thenAnswer((_) async {});
    when(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayBitcoin, true),
    ).thenAnswer((_) async {});
    when(
      () => externalReceiveWallets.setAutoSweepForAccount(btcpayBitcoin, true),
    ).thenAnswer((_) async {});

    await cubit.setPaymentPageAutoSweep(false);
    await cubit.setBtcpayLiquidHideWallet(false);
    await cubit.setBtcpayBitcoinAutoSweep(true);
    await cubit.setBtcpayBitcoinHideWallet(true);

    expect(cubit.state.paymentPageAutoSweep, isFalse);
    expect(cubit.state.btcpayLiquidHideWallet, isFalse);
    expect(cubit.state.btcpayBitcoinAutoSweep, isTrue);
    expect(cubit.state.btcpayBitcoinHideWallet, isTrue);
    expect(cubit.state.isSavingSettings, isFalse);
    verify(
      () => externalReceiveWallets.setAutoSweepForAccount(paymentPage, false),
    ).called(1);
    verify(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayLiquid, false),
    ).called(1);
    verify(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayBitcoin, true),
    ).called(1);
    verify(
      () => externalReceiveWallets.setAutoSweepForAccount(btcpayBitcoin, true),
    ).called(1);
  });

  test('updates settings with testnet account keys on testnet', () async {
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) async => _settings(environment: Environment.testnet));
    final paymentPage = ExternalReceiveWalletPurpose.paymentPage
        .liquidAccountKey(isTestnet: true);
    final btcpayBitcoin = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
      isTestnet: true,
    );
    when(
      () => externalReceiveWallets.setAutoSweepForAccount(paymentPage, false),
    ).thenAnswer((_) async {});
    when(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayBitcoin, true),
    ).thenAnswer((_) async {});

    await cubit.setPaymentPageAutoSweep(false);
    await cubit.setBtcpayBitcoinHideWallet(true);

    verify(
      () => externalReceiveWallets.setAutoSweepForAccount(paymentPage, false),
    ).called(1);
    verify(
      () =>
          externalReceiveWallets.setHiddenOnHomeForAccount(btcpayBitcoin, true),
    ).called(1);
  });

  test('restores reserved Get Paid wallets for current environment', () async {
    when(() => getSettings.execute()).thenAnswer((_) async => _settings());
    when(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) async => _result());

    await cubit.restoreGetPaidWallets();

    expect(cubit.state.isRestoringWallets, isFalse);
    expect(cubit.state.restoreOutcomes, hasLength(2));
    expect(
      cubit.state.restoreOutcomes?.map((outcome) => outcome.accountKey.purpose),
      [
        ExternalReceiveWalletPurpose.lightningAddress,
        ExternalReceiveWalletPurpose.paymentPage,
      ],
    );
    expect(cubit.state.restoreFailed, isFalse);
    verify(() => getSettings.execute()).called(1);
    verify(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    ).called(1);
  });

  test(
    'maps restore exceptions to failed state without raw error details',
    () async {
      when(() => getSettings.execute()).thenAnswer((_) async => _settings());
      when(
        () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
          environment: Environment.mainnet,
        ),
      ).thenThrow(Exception('seed details'));

      await cubit.restoreGetPaidWallets();

      expect(cubit.state.isRestoringWallets, isFalse);
      expect(cubit.state.restoreOutcomes, isNull);
      expect(cubit.state.restoreFailed, isTrue);
    },
  );

  test('does not restore wallets after close during settings lookup', () async {
    final settingsCompleter = Completer<SettingsEntity>();
    when(
      () => getSettings.execute(),
    ).thenAnswer((_) => settingsCompleter.future);

    final restore = cubit.restoreGetPaidWallets();
    await cubit.close();
    settingsCompleter.complete(_settings());

    await expectLater(restore, completes);
    verifyNever(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: any(named: 'environment'),
      ),
    );
  });

  test('does not emit after close while restore is in flight', () async {
    final completer = Completer<List<ExternalReceiveWalletRestoreOutcome>>();
    when(() => getSettings.execute()).thenAnswer((_) async => _settings());
    when(
      () => externalReceiveWallets.restoreReservedExternalReceiveWallets(
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) => completer.future);

    final restore = cubit.restoreGetPaidWallets();
    await cubit.close();
    completer.complete(_result());

    await expectLater(restore, completes);
  });
}

SettingsEntity _settings({Environment environment = Environment.mainnet}) {
  return SettingsEntity(
    environment: environment,
    bitcoinUnit: BitcoinUnit.sats,
    currencyCode: 'CAD',
  );
}

List<ExternalReceiveWalletRestoreOutcome> _result() {
  return [
    ExternalReceiveWalletRestoreOutcome(
      accountKey: ExternalReceiveWalletPurpose.lightningAddress
          .liquidAccountKey(isTestnet: false),
      status: ExternalReceiveWalletRestoreOutcomeStatus.existing,
    ),
    ExternalReceiveWalletRestoreOutcome(
      accountKey: ExternalReceiveWalletPurpose.paymentPage.liquidAccountKey(
        isTestnet: false,
      ),
      status: ExternalReceiveWalletRestoreOutcomeStatus.created,
    ),
  ];
}
