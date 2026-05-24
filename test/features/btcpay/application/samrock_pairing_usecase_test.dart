import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/btcpay/application/application_errors.dart';
import 'package:bb_mobile/features/btcpay/application/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/application/ports/btcpay_connection_store.dart';
import 'package:bb_mobile/features/btcpay/application/ports/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/application/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeterministicWalletsFacade extends Mock
    implements DeterministicWalletsFacade {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockSamRockPairingServicePort extends Mock
    implements SamRockPairingServicePort {}

class _MockBtcpayConnectionStore extends Mock
    implements BtcpayConnectionStore {}

void main() {
  const pairingUrl =
      'https://btcpay.example.com/plugins/store123/samrock/protocol?otp=123&setup=btc,lbtc,btcln';
  final pairingRequest = const SamRockPairingRequestParser().parse(pairingUrl);
  const settings = SettingsEntity(
    environment: Environment.mainnet,
    bitcoinUnit: BitcoinUnit.sats,
    currencyCode: 'USD',
  );

  setUpAll(() {
    registerFallbackValue(pairingRequest);
    registerFallbackValue(
      const DeterministicWalletsRequest(
        bip85Index: 77,
        bip85Alias: 'BTCPay',
        environment: Environment.mainnet,
        walletSpecs: [],
      ),
    );
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(
      BtcpayConnection(
        environment: Environment.mainnet,
        serverUrl: 'https://btcpay.example.com',
        storeId: 'store123',
        capabilities: const [],
        walletNetworks: const [],
        status: BtcpayConnectionStatus.uncertain,
        pairedAt: null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
  });

  test('parses SamRock pairing URL capabilities', () {
    final request = const SamRockPairingRequestParser().parse(pairingUrl);

    expect(request.otp, '123');
    expect(request.storeId, 'store123');
    expect(request.supportsBitcoinChain, isTrue);
    expect(request.supportsLiquidChain, isTrue);
    expect(request.supportsLightning, isTrue);
    expect(btcpayServerUrlFor(request), 'https://btcpay.example.com');
  });

  test('rejects unknown SamRock setup capabilities', () {
    const url =
        'https://btcpay.example.com/plugins/store123/samrock/protocol?otp=123&setup=btc,unknown';

    expect(
      () => const SamRockPairingRequestParser().parse(url),
      throwsA(isA<SamRockPairingRequestException>()),
    );
  });

  test('builds setup payload from prepared Bitcoin and Liquid wallets', () {
    final request = const SamRockPairingRequestParser().parse(pairingUrl);
    final payload = const SamRockSetupPayloadBuilder().build(
      request: request,
      preparedWallets: PreparedDeterministicWallets(
        wallets: [
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            wallet: _wallet(
              Network.bitcoinMainnet,
              externalDescriptor: 'btc-desc',
            ),
            created: false,
          ),
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            wallet: _wallet(
              Network.liquidMainnet,
              externalDescriptor: 'lbtc-desc',
            ),
            created: false,
          ),
        ],
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: false,
      ),
    );

    expect(payload['BTC'], {'Descriptor': 'btc-desc'});
    expect(payload['LBTC'], {'Descriptor': 'lbtc-desc'});
    expect(payload['BTCLN'], {
      'Type': 'Boltz',
      'LBTC': {'Descriptor': 'lbtc-desc'},
    });
  });

  test(
    'rolls back created wallets before descriptor submission failure',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionStore = _MockBtcpayConnectionStore();
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            wallet: _wallet(Network.bitcoinMainnet, externalDescriptor: ''),
            created: true,
          ),
        ],
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionStore: connectionStore,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).thenAnswer((_) async {});

      await expectLater(
        usecase.execute(pairingUrl: pairingUrl),
        throwsA(isA<BtcpayPairingException>()),
      );
      verify(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).called(1);
      verifyNever(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      );
    },
  );

  test(
    'keeps wallets when server rejects after descriptor submission',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionStore = _MockBtcpayConnectionStore();
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            wallet: _wallet(
              Network.bitcoinMainnet,
              externalDescriptor: 'btc-desc',
            ),
            created: true,
          ),
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            wallet: _wallet(
              Network.liquidMainnet,
              externalDescriptor: 'lbtc-desc',
            ),
            created: true,
          ),
        ],
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionStore: connectionStore,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => connectionStore.saveConnection(any()),
      ).thenAnswer((_) async {});
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const SamRockPairingResponse(success: false));

      await expectLater(
        usecase.execute(pairingUrl: pairingUrl),
        throwsA(isA<BtcpayPairingException>()),
      );
      verifyNever(() => connectionStore.saveConnection(any()));
      verifyNever(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      );
    },
  );

  test('reports uncertain state when final local save fails', () async {
    final deterministicWallets = _MockDeterministicWalletsFacade();
    final getSettings = _MockGetSettingsUsecase();
    final pairingService = _MockSamRockPairingServicePort();
    final connectionStore = _MockBtcpayConnectionStore();
    final preparedWallets = PreparedDeterministicWallets(
      wallets: [
        PreparedDeterministicWallet(
          specId: BtcpayWalletConstants.bitcoinSpecId,
          wallet: _wallet(
            Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
          ),
          created: true,
        ),
        PreparedDeterministicWallet(
          specId: BtcpayWalletConstants.liquidSpecId,
          wallet: _wallet(
            Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
          ),
          created: true,
        ),
      ],
      childSeedFingerprint: '0123abcd',
      childSeedStoredDuringAttempt: true,
    );
    final usecase = CompleteBtcpaySamRockPairingUsecase(
      getSettings: getSettings,
      parser: const SamRockPairingRequestParser(),
      deterministicWallets: deterministicWallets,
      pairingService: pairingService,
      connectionStore: connectionStore,
    );
    var saveCalls = 0;
    when(() => getSettings.execute()).thenAnswer((_) async => settings);
    when(
      () => deterministicWallets.prepare(any()),
    ).thenAnswer((_) async => preparedWallets);
    when(() => connectionStore.saveConnection(any())).thenAnswer((_) async {
      saveCalls += 1;
      if (saveCalls == 1) throw Exception('disk full');
    });
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const SamRockPairingResponse(success: true));

    await expectLater(
      usecase.execute(pairingUrl: pairingUrl),
      throwsA(
        isA<BtcpayPairingException>().having(
          (error) => error.type,
          'type',
          BtcpayPairingExceptionType.uncertain,
        ),
      ),
    );
    expect(saveCalls, 2);
    verifyNever(
      () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
    );
  });
}

Wallet _wallet(Network network, {required String externalDescriptor}) {
  return Wallet(
    origin: network.name,
    label: network.name,
    network: network,
    isDefault: false,
    masterFingerprint: 'fingerprint',
    xpubFingerprint: 'xpub-fingerprint',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: externalDescriptor,
    internalPublicDescriptor: 'internal-desc',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
