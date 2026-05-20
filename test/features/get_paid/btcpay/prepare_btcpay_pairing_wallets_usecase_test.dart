import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/external_receive_wallets/public/external_receive_wallets.dart';
import 'package:bb_mobile/features/get_paid/btcpay/application/prepare_btcpay_pairing_wallets_usecase.dart';
import 'package:bb_mobile/features/get_paid/btcpay/domain/samrock_pairing_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetSettings extends Mock implements GetSettingsUsecase {}

class _MockExternalReceiveWallets extends Mock
    implements ExternalReceiveWalletsFacade {}

void main() {
  late _MockGetSettings getSettings;
  late _MockExternalReceiveWallets externalReceiveWallets;
  late PrepareBtcpayPairingWalletsUsecase usecase;

  setUpAll(() {
    registerFallbackValue(Environment.mainnet);
    registerFallbackValue(ExternalReceiveWalletPurpose.btcpay);
    registerFallbackValue(
      ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(isTestnet: false),
    );
  });

  setUp(() {
    getSettings = _MockGetSettings();
    externalReceiveWallets = _MockExternalReceiveWallets();
    usecase = PrepareBtcpayPairingWalletsUsecase(
      getSettings: getSettings,
      externalReceiveWallets: externalReceiveWallets,
    );

    when(() => getSettings.execute()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    when(
      () => externalReceiveWallets.get(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => externalReceiveWallets.create(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
        publishManifest: any(named: 'publishManifest'),
      ),
    ).thenAnswer((invocation) async {
      final key =
          invocation.namedArguments[#accountKey]
              as ExternalReceiveWalletAccountKey;
      return _wallet(key.walletLabel, network: key.network);
    });
    when(
      () => externalReceiveWallets.deleteCreated(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
        expectedWalletId: any(named: 'expectedWalletId'),
      ),
    ).thenAnswer((_) async {});
  });

  test(
    'prepares requested BTCPay Bitcoin and Liquid wallets without publishing',
    () async {
      final result = await usecase.execute(
        request: _request('btc-chain,liquid-chain'),
      );

      expect(result.wallets.map((wallet) => wallet.network), [
        BtcpayPairingWalletNetwork.bitcoin,
        BtcpayPairingWalletNetwork.liquid,
      ]);
      verify(
        () => externalReceiveWallets.create(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
            isTestnet: false,
          ),
          publishManifest: false,
        ),
      ).called(1);
      verify(
        () => externalReceiveWallets.create(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
            isTestnet: false,
          ),
          publishManifest: false,
        ),
      ).called(1);
    },
  );

  test('returns existing wallets without recreating them', () async {
    final existing = _wallet('BTCPay-LBTC', network: Network.liquidMainnet);
    when(
      () => externalReceiveWallets.get(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
      ),
    ).thenAnswer((_) async => existing);

    final result = await usecase.execute(request: _request('liquid-chain'));

    expect(result.wallets.single.wallet, same(existing));
    verifyNever(
      () => externalReceiveWallets.create(
        environment: any(named: 'environment'),
        purpose: any(named: 'purpose'),
        accountKey: any(named: 'accountKey'),
        publishManifest: any(named: 'publishManifest'),
      ),
    );
  });

  test('uses testnet account keys in testnet environment', () async {
    when(() => getSettings.execute()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.testnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );

    await usecase.execute(request: _request('btc-chain,liquid-chain'));

    verify(
      () => externalReceiveWallets.create(
        environment: Environment.testnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
          isTestnet: true,
        ),
        publishManifest: false,
      ),
    ).called(1);
    verify(
      () => externalReceiveWallets.create(
        environment: Environment.testnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
          isTestnet: true,
        ),
        publishManifest: false,
      ),
    ).called(1);
  });

  test('creates the Liquid wallet for Lightning setup', () async {
    final result = await usecase.execute(request: _request('btc-ln'));

    expect(result.wallets.map((wallet) => wallet.network), [
      BtcpayPairingWalletNetwork.liquid,
    ]);
    verify(
      () => externalReceiveWallets.create(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
          isTestnet: false,
        ),
        publishManifest: false,
      ),
    ).called(1);
  });

  test(
    'rolls back wallets created before a later requested wallet fails',
    () async {
      final bitcoinKey = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
        isTestnet: false,
      );
      final liquidKey = ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
        isTestnet: false,
      );
      when(
        () => externalReceiveWallets.create(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: bitcoinKey,
          publishManifest: any(named: 'publishManifest'),
        ),
      ).thenAnswer(
        (_) async => _wallet('BTCPay-BTC', network: Network.bitcoinMainnet),
      );
      when(
        () => externalReceiveWallets.create(
          environment: any(named: 'environment'),
          purpose: any(named: 'purpose'),
          accountKey: liquidKey,
          publishManifest: any(named: 'publishManifest'),
        ),
      ).thenThrow(Exception('liquid failed'));

      await expectLater(
        usecase.execute(request: _request('btc-chain,liquid-chain')),
        throwsA(isA<Exception>()),
      );

      verify(
        () => externalReceiveWallets.deleteCreated(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: bitcoinKey,
          expectedWalletId: 'BTCPay-BTC',
        ),
      ).called(1);
      verifyNever(
        () => externalReceiveWallets.deleteCreated(
          environment: Environment.mainnet,
          purpose: ExternalReceiveWalletPurpose.btcpay,
          accountKey: liquidKey,
          expectedWalletId: any(named: 'expectedWalletId'),
        ),
      );
    },
  );

  test('rollback deletes only wallets created during pairing', () async {
    final createdKey = ExternalReceiveWalletPurpose.btcpay.bitcoinAccountKey(
      isTestnet: false,
    );
    final existingKey = ExternalReceiveWalletPurpose.btcpay.liquidAccountKey(
      isTestnet: false,
    );
    final result = PrepareBtcpayPairingWalletsResult(
      wallets: [
        PrepareBtcpayPairingWalletResult(
          network: BtcpayPairingWalletNetwork.bitcoin,
          accountKey: createdKey,
          wallet: _wallet('BTCPay-BTC', network: Network.bitcoinMainnet),
          created: true,
        ),
        PrepareBtcpayPairingWalletResult(
          network: BtcpayPairingWalletNetwork.liquid,
          accountKey: existingKey,
          wallet: _wallet('BTCPay-LBTC', network: Network.liquidMainnet),
          created: false,
        ),
      ],
    );

    await usecase.rollbackCreatedWallets(result);

    verify(
      () => externalReceiveWallets.deleteCreated(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: createdKey,
        expectedWalletId: 'BTCPay-BTC',
      ),
    ).called(1);
    verifyNever(
      () => externalReceiveWallets.deleteCreated(
        environment: Environment.mainnet,
        purpose: ExternalReceiveWalletPurpose.btcpay,
        accountKey: existingKey,
        expectedWalletId: 'BTCPay-LBTC',
      ),
    );
  });
}

SamRockPairingRequest _request(String setup) {
  return const SamRockPairingRequestParser().parse(
    'https://btcpay.example/plugins/x/samrock/protocol?setup=$setup&otp=otp',
  );
}

Wallet _wallet(String label, {required Network network}) {
  return Wallet(
    origin: label,
    label: label,
    network: network,
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
