import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_bitcoin_transaction_usecase.dart';
import 'package:bb_mobile/core/blockchain/domain/usecases/broadcast_liquid_transaction_usecase.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/fees/domain/fees_entity.dart';
import 'package:bb_mobile/core/fees/domain/get_network_fees_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/swaps/domain/entity/auto_swap.dart';
import 'package:bb_mobile/core/swaps/domain/usecases/get_auto_swap_settings_usecase.dart';
import 'package:bb_mobile/core/wallet/data/repositories/bitcoin_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/liquid_wallet_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_address_repository.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet_address.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_purpose.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/external_receive_wallets/external_receive_wallet_errors.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/get_external_receive_wallet_usecase.dart';
import 'package:bb_mobile/features/external_receive_wallets/usecases/sweep_external_receive_wallet_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWallet extends Mock implements GetExternalReceiveWalletUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockWalletAddressRepository extends Mock
    implements WalletAddressRepository {}

class _MockLiquidWalletRepository extends Mock
    implements LiquidWalletRepository {}

class _MockBitcoinWalletRepository extends Mock
    implements BitcoinWalletRepository {}

class _MockBroadcastLiquidTransactionUsecase extends Mock
    implements BroadcastLiquidTransactionUsecase {}

class _MockBroadcastBitcoinTransactionUsecase extends Mock
    implements BroadcastBitcoinTransactionUsecase {}

class _MockGetNetworkFeesUsecase extends Mock
    implements GetNetworkFeesUsecase {}

class _MockGetAutoSwapSettingsUsecase extends Mock
    implements GetAutoSwapSettingsUsecase {}

class _MockLabelsFacade extends Mock implements LabelsFacade {}

Wallet _liquidWallet({
  required String id,
  required String label,
  bool isDefault = false,
  Network network = Network.liquidMainnet,
  BigInt? balanceSat,
}) => Wallet(
  origin: id,
  network: network,
  isDefault: isDefault,
  masterFingerprint: 'aabbccdd',
  xpubFingerprint: 'aabbccdd',
  scriptType: ScriptType.bip84,
  xpub: 'xpubLiquid',
  externalPublicDescriptor: 'ct(slip77(...),elwpkh(xpubLiquid/0/*))',
  internalPublicDescriptor: 'ct(slip77(...),elwpkh(xpubLiquid/1/*))',
  signer: SignerEntity.local,
  signerDevice: null,
  balanceSat: balanceSat ?? BigInt.from(1000),
  label: label,
);

WalletAddress _address() => WalletAddress(
  walletId: 'default-liquid',
  index: 1,
  address: 'lq1destination',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.lightningAddress);
    registerFallbackValue(const NetworkFee.relative(0.1));
    registerFallbackValue(NewLabel.tx(transactionId: 'txid', label: 'label'));
  });

  late _MockGetWallet getWallet;
  late _MockWalletRepository walletRepository;
  late _MockWalletAddressRepository walletAddressRepository;
  late _MockLiquidWalletRepository liquidWalletRepository;
  late _MockBitcoinWalletRepository bitcoinWalletRepository;
  late _MockBroadcastLiquidTransactionUsecase broadcast;
  late _MockBroadcastBitcoinTransactionUsecase broadcastBitcoin;
  late _MockGetNetworkFeesUsecase getNetworkFees;
  late _MockGetAutoSwapSettingsUsecase getAutoSwapSettings;
  late _MockLabelsFacade labelsFacade;
  late SweepExternalReceiveWalletUsecase usecase;

  setUp(() {
    getWallet = _MockGetWallet();
    walletRepository = _MockWalletRepository();
    walletAddressRepository = _MockWalletAddressRepository();
    liquidWalletRepository = _MockLiquidWalletRepository();
    bitcoinWalletRepository = _MockBitcoinWalletRepository();
    broadcast = _MockBroadcastLiquidTransactionUsecase();
    broadcastBitcoin = _MockBroadcastBitcoinTransactionUsecase();
    getNetworkFees = _MockGetNetworkFeesUsecase();
    getAutoSwapSettings = _MockGetAutoSwapSettingsUsecase();
    labelsFacade = _MockLabelsFacade();
    usecase = SweepExternalReceiveWalletUsecase(
      getWallet: getWallet,
      walletRepository: walletRepository,
      walletAddressRepository: walletAddressRepository,
      liquidWalletRepository: liquidWalletRepository,
      bitcoinWalletRepository: bitcoinWalletRepository,
      broadcastLiquid: broadcast,
      broadcastBitcoin: broadcastBitcoin,
      getNetworkFees: getNetworkFees,
      getAutoSwapSettings: getAutoSwapSettings,
      labelsFacade: labelsFacade,
    );

    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer(
      (_) async => _liquidWallet(
        id: 'la-wallet',
        label: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
      ),
    );
    when(
      () => walletRepository.getWallets(
        environment: any(named: 'environment'),
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyLiquid: any(named: 'onlyLiquid'),
      ),
    ).thenAnswer(
      (_) async => [
        _liquidWallet(
          id: 'default-liquid',
          label: 'Instant Payments',
          isDefault: true,
        ),
      ],
    );
    when(
      () => walletAddressRepository.generateNewReceiveAddress(
        walletId: any(named: 'walletId'),
      ),
    ).thenAnswer((_) async => _address());
    when(
      () => liquidWalletRepository.buildPset(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        drain: any(named: 'drain'),
      ),
    ).thenAnswer((_) async => 'pset');
    when(
      () => liquidWalletRepository.signPset(
        pset: any(named: 'pset'),
        walletId: any(named: 'walletId'),
      ),
    ).thenAnswer((_) async => 'signed-pset');
    when(
      () => broadcast.execute(any(), isTestnet: any(named: 'isTestnet')),
    ).thenAnswer((_) async => 'txid');
    when(() => getNetworkFees.execute(isLiquid: false)).thenAnswer(
      (_) async => const FeeOptions(
        fastest: NetworkFee.relative(10),
        economic: NetworkFee.relative(2),
        slow: NetworkFee.relative(1),
      ),
    );
    when(
      () => bitcoinWalletRepository.buildPsbt(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        drain: any(named: 'drain'),
      ),
    ).thenAnswer((_) async => 'psbt');
    when(
      () => bitcoinWalletRepository.getTxFeeAmount(psbt: any(named: 'psbt')),
    ).thenAnswer((_) async => 20);
    when(
      () => getAutoSwapSettings.execute(),
    ).thenAnswer((_) async => const AutoSwap(feeThresholdPercent: 3.0));
    when(
      () => bitcoinWalletRepository.signPsbt(
        any(),
        walletId: any(named: 'walletId'),
      ),
    ).thenAnswer((_) async => 'signed-psbt');
    when(
      () => broadcastBitcoin.execute(any(), isPsbt: any(named: 'isPsbt')),
    ).thenAnswer((_) async => 'bitcoin-txid');
    when(() => labelsFacade.store(any())).thenAnswer(
      (_) async => Label.tx(
        id: 1,
        transactionId: 'txid',
        label: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
      ),
    );
  });

  test('sweeps the Lightning Address receive wallet when requested', () async {
    final txid = await usecase.execute(
      isTestnet: false,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      expectedWalletId: 'la-wallet',
    );

    expect(txid, 'txid');
    verify(
      () => getWallet.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
      ),
    ).called(1);
    final label =
        verify(() => labelsFacade.store(captureAny())).captured.single
            as NewLabel;
    expect(
      label.label,
      ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
    );
    expect(label.reference, 'txid');
    expect(label.origin, 'la-wallet');
  });

  test('returns txid when post-broadcast label transfer fails', () async {
    when(() => labelsFacade.store(any())).thenThrow(Exception('db locked'));

    final txid = await usecase.execute(
      isTestnet: false,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      expectedWalletId: 'la-wallet',
    );

    expect(txid, 'txid');
    verify(() => broadcast.execute('signed-pset', isTestnet: false)).called(1);
    verify(() => labelsFacade.store(any())).called(1);
  });

  test('sweeps Payment Page Liquid receive wallet when requested', () async {
    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: ExternalReceiveWalletPurpose.paymentPage,
      ),
    ).thenAnswer(
      (_) async => _liquidWallet(
        id: 'payment-page-wallet',
        label: ReservedExternalReceiveWalletLabel.paymentPageLiquid,
      ),
    );

    final txid = await usecase.execute(
      isTestnet: false,
      purpose: ExternalReceiveWalletPurpose.paymentPage,
      expectedWalletId: 'payment-page-wallet',
    );

    expect(txid, 'txid');
    final label =
        verify(() => labelsFacade.store(captureAny())).captured.single
            as NewLabel;
    expect(label.label, ReservedExternalReceiveWalletLabel.paymentPageLiquid);
    expect(label.origin, 'payment-page-wallet');
  });

  test(
    'does not sweep when resolved wallet differs from synced wallet',
    () async {
      final txid = await usecase.execute(
        isTestnet: false,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
        expectedWalletId: 'other-wallet',
      );

      expect(txid, isNull);
      verifyNever(
        () => broadcast.execute(any(), isTestnet: any(named: 'isTestnet')),
      );
      verifyNever(() => labelsFacade.store(any()));
    },
  );

  test('sweeps BTCPay Bitcoin wallet when fee is under autoswap cap', () async {
    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer(
      (_) async => _liquidWallet(
        id: 'btcpay-bitcoin',
        label: ReservedExternalReceiveWalletLabel.btcpayBitcoin,
        network: Network.bitcoinMainnet,
        balanceSat: BigInt.from(10 * 1000),
      ),
    );
    when(
      () => walletRepository.getWallets(
        environment: any(named: 'environment'),
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyBitcoin: any(named: 'onlyBitcoin'),
      ),
    ).thenAnswer(
      (_) async => [
        _liquidWallet(
          id: 'default-bitcoin',
          label: 'Secure Bitcoin',
          isDefault: true,
          network: Network.bitcoinMainnet,
        ),
      ],
    );
    when(
      () => walletAddressRepository.generateNewReceiveAddress(
        walletId: 'default-bitcoin',
      ),
    ).thenAnswer(
      (_) async => WalletAddress(
        walletId: 'default-bitcoin',
        index: 1,
        address: 'bc1destination',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    final txid = await usecase.execute(
      isTestnet: false,
      purpose: ExternalReceiveWalletPurpose.btcpay,
      expectedWalletId: 'btcpay-bitcoin',
      accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      ),
    );

    expect(txid, 'bitcoin-txid');
    verify(
      () => getWallet.execute(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: false,
        ),
      ),
    ).called(1);
    verify(
      () => walletAddressRepository.generateNewReceiveAddress(
        walletId: 'default-bitcoin',
      ),
    ).called(1);
    verifyNever(
      () => walletAddressRepository.getLastRevealedReceiveAddress(
        walletId: any(named: 'walletId'),
      ),
    );
    verify(
      () => bitcoinWalletRepository.buildPsbt(
        walletId: 'btcpay-bitcoin',
        address: 'bc1destination',
        networkFee: const NetworkFee.relative(2),
        drain: true,
      ),
    ).called(1);
    verify(
      () => broadcastBitcoin.execute('signed-psbt', isPsbt: true),
    ).called(1);
    final label =
        verify(() => labelsFacade.store(captureAny())).captured.single
            as NewLabel;
    expect(label.label, ReservedExternalReceiveWalletLabel.btcpayBitcoin);
    expect(label.origin, 'btcpay-bitcoin');
  });

  test(
    'skips BTCPay Bitcoin autosweep when fee exceeds autoswap cap',
    () async {
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: any(named: 'accountKey'),
        ),
      ).thenAnswer(
        (_) async => _liquidWallet(
          id: 'btcpay-bitcoin',
          label: ReservedExternalReceiveWalletLabel.btcpayBitcoin,
          network: Network.bitcoinMainnet,
          balanceSat: BigInt.from(1000),
        ),
      );
      when(
        () => walletRepository.getWallets(
          environment: any(named: 'environment'),
          onlyDefaults: any(named: 'onlyDefaults'),
          onlyBitcoin: any(named: 'onlyBitcoin'),
        ),
      ).thenAnswer(
        (_) async => [
          _liquidWallet(
            id: 'default-bitcoin',
            label: 'Secure Bitcoin',
            isDefault: true,
            network: Network.bitcoinMainnet,
          ),
        ],
      );
      when(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: 'default-bitcoin',
        ),
      ).thenAnswer(
        (_) async => WalletAddress(
          walletId: 'default-bitcoin',
          index: 1,
          address: 'bc1destination',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      when(
        () => bitcoinWalletRepository.getTxFeeAmount(psbt: any(named: 'psbt')),
      ).thenAnswer((_) async => 100);

      final txid = await usecase.execute(
        isTestnet: false,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        expectedWalletId: 'btcpay-bitcoin',
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: false,
        ),
      );

      expect(txid, isNull);
      verifyNever(
        () => bitcoinWalletRepository.signPsbt(
          any(),
          walletId: any(named: 'walletId'),
        ),
      );
      verifyNever(
        () => broadcastBitcoin.execute(any(), isPsbt: any(named: 'isPsbt')),
      );
      verifyNever(() => labelsFacade.store(any()));
    },
  );

  test(
    'does nothing when the Lightning Address wallet does not exist',
    () async {
      when(
        () => getWallet.execute(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
        ),
      ).thenAnswer((_) async => null);

      final txid = await usecase.execute(
        isTestnet: false,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
        expectedWalletId: 'la-wallet',
      );

      expect(txid, isNull);
      verifyNever(
        () => walletAddressRepository.generateNewReceiveAddress(
          walletId: any(named: 'walletId'),
        ),
      );
      verifyNever(
        () => liquidWalletRepository.buildPset(
          walletId: any(named: 'walletId'),
          address: any(named: 'address'),
          networkFee: any(named: 'networkFee'),
          drain: any(named: 'drain'),
        ),
      );
      verifyNever(() => labelsFacade.store(any()));
    },
  );

  test('does nothing when the Lightning Address wallet is dust only', () async {
    when(
      () => getWallet.execute(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
      ),
    ).thenAnswer(
      (_) async => _liquidWallet(
        id: 'la-wallet',
        label: ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
        balanceSat: BigInt.from(100),
      ),
    );

    final txid = await usecase.execute(
      isTestnet: false,
      purpose: ExternalReceiveWalletPurpose.lightningAddress,
      expectedWalletId: 'la-wallet',
    );

    expect(txid, isNull);
    verifyNever(
      () => walletAddressRepository.generateNewReceiveAddress(
        walletId: any(named: 'walletId'),
      ),
    );
    verifyNever(
      () => liquidWalletRepository.buildPset(
        walletId: any(named: 'walletId'),
        address: any(named: 'address'),
        networkFee: any(named: 'networkFee'),
        drain: any(named: 'drain'),
      ),
    );
    verifyNever(() => labelsFacade.store(any()));
  });

  test('throws when the default Liquid wallet is missing', () async {
    when(
      () => walletRepository.getWallets(
        environment: any(named: 'environment'),
        onlyDefaults: any(named: 'onlyDefaults'),
        onlyLiquid: any(named: 'onlyLiquid'),
      ),
    ).thenAnswer((_) async => []);

    await expectLater(
      usecase.execute(
        isTestnet: false,
        purpose: ExternalReceiveWalletPurpose.lightningAddress,
        expectedWalletId: 'la-wallet',
      ),
      throwsA(isA<ExternalReceiveWalletSweepException>()),
    );
  });
}
