import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/apply_wallet_behavior_defaults_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_error.dart';
import 'package:bb_mobile/features/btcpay/domain/usecases/complete_btcpay_samrock_pairing_usecase.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection_repository.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_service_port.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_setup_payload_builder.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_connection.dart';
import 'package:bb_mobile/features/btcpay/domain/btcpay_wallet.dart';
import 'package:bb_mobile/features/btcpay/domain/samrock_pairing_request.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeterministicWalletsFacade extends Mock
    implements DeterministicWalletsFacade {}

class _MockGetSettingsUsecase extends Mock implements GetSettingsUsecase {}

class _MockSamRockPairingServicePort extends Mock
    implements SamRockPairingServicePort {}

class _MockBtcpayConnectionRepository extends Mock
    implements BtcpayConnectionRepository {}

class _MockApplyWalletBehaviorDefaultsUsecase extends Mock
    implements ApplyWalletBehaviorDefaultsUsecase {}

class _MockKeychainManifestFacade extends Mock
    implements KeychainManifestFacade {}

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
        bip85Index: 100,
        bip85Alias: 'BTCPay',
        environment: Environment.mainnet,
        walletSpecs: [],
      ),
    );
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(
      const KeychainManifestReservedDerivationRequest(
        reservationId: 'btcpay_wallet_seed',
        parentFingerprint: 'fedcba98',
        materializations: [],
      ),
    );
    registerFallbackValue(_recordedKeychainEntries);
    registerFallbackValue(<KeychainManifestRecordedMaterialization>[]);
    registerFallbackValue(Network.bitcoinMainnet);
    registerFallbackValue(ScriptType.bip84);
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
            walletId: Network.bitcoinMainnet.name,
            network: Network.bitcoinMainnet,
            scriptType: ScriptType.bip84,
            label: Network.bitcoinMainnet.name,
            externalPublicDescriptor: 'btc-desc',
            internalPublicDescriptor: 'internal-desc',
            created: false,
          ),
          PreparedDeterministicWallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            walletId: Network.liquidMainnet.name,
            network: Network.liquidMainnet,
            scriptType: ScriptType.bip84,
            label: Network.liquidMainnet.name,
            externalPublicDescriptor: 'lbtc-desc',
            internalPublicDescriptor: 'internal-desc',
            created: false,
          ),
        ],
        parentFingerprint: 'fedcba98',
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
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      _stubKeychainManifest(keychainManifest);
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: '',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
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
        throwsA(
          isA<BtcpayPairingException>().having(
            (exception) => exception.type,
            'type',
            BtcpayPairingExceptionType.generic,
          ),
        ),
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
    'rolls back local wallets when server rejects after descriptor submission',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      _stubKeychainManifest(keychainManifest);
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => connectionRepository.saveConnection(any()),
      ).thenAnswer((_) async {});
      when(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).thenAnswer((_) async {});
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const SamRockPairingResponse(success: false));

      await expectLater(
        usecase.execute(pairingUrl: pairingUrl),
        throwsA(
          isA<BtcpayPairingException>().having(
            (exception) => exception.type,
            'type',
            BtcpayPairingExceptionType.rejected,
          ),
        ),
      );
      verifyNever(() => connectionRepository.saveConnection(any()));
      verify(
        () => keychainManifest.deleteInsertedMaterializations(any()),
      ).called(1);
      verify(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).called(1);
    },
  );

  test(
    'keeps keychain entries when server rejects and wallet rollback fails',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      _stubKeychainManifest(keychainManifest);
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).thenThrow(StateError('rollback failed'));
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const SamRockPairingResponse(success: false));

      await expectLater(
        usecase.execute(pairingUrl: pairingUrl),
        throwsA(
          isA<BtcpayPairingException>().having(
            (exception) => exception.type,
            'type',
            BtcpayPairingExceptionType.uncertain,
          ),
        ),
      );
      verifyNever(() => keychainManifest.deleteInsertedMaterializations(any()));
      verify(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).called(1);
    },
  );

  test(
    'does not delete reused keychain entries when server rejects retry',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      when(() => keychainManifest.recordReservedDerivation(any())).thenAnswer((
        _,
      ) async {
        return const KeychainManifestRecordReservedDerivationResult.forTesting(
          insertedMaterializations: [],
        );
      });
      when(
        () => keychainManifest.deleteInsertedMaterializations(any()),
      ).thenAnswer((_) async {});
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: false,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: false,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
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
      verifyNever(() => keychainManifest.deleteInsertedMaterializations(any()));
      verify(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).called(1);
    },
  );

  test('reports uncertain state when final local save fails', () async {
    final deterministicWallets = _MockDeterministicWalletsFacade();
    final getSettings = _MockGetSettingsUsecase();
    final pairingService = _MockSamRockPairingServicePort();
    final connectionRepository = _MockBtcpayConnectionRepository();
    final applyWalletBehaviorDefaults =
        _MockApplyWalletBehaviorDefaultsUsecase();
    final keychainManifest = _MockKeychainManifestFacade();
    _stubKeychainManifest(keychainManifest);
    final preparedWallets = PreparedDeterministicWallets(
      wallets: [
        _wallet(
          specId: BtcpayWalletConstants.bitcoinSpecId,
          network: Network.bitcoinMainnet,
          externalDescriptor: 'btc-desc',
          created: true,
        ),
        _wallet(
          specId: BtcpayWalletConstants.liquidSpecId,
          network: Network.liquidMainnet,
          externalDescriptor: 'lbtc-desc',
          created: true,
        ),
      ],
      parentFingerprint: 'fedcba98',
      childSeedFingerprint: '0123abcd',
      childSeedStoredDuringAttempt: true,
    );
    final usecase = CompleteBtcpaySamRockPairingUsecase(
      getSettings: getSettings,
      parser: const SamRockPairingRequestParser(),
      deterministicWallets: deterministicWallets,
      pairingService: pairingService,
      connectionRepository: connectionRepository,
      applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
      bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
    );
    var saveCalls = 0;
    when(() => getSettings.execute()).thenAnswer((_) async => settings);
    when(
      () => deterministicWallets.prepare(any()),
    ).thenAnswer((_) async => preparedWallets);
    when(() => connectionRepository.saveConnection(any())).thenAnswer((_) async {
      saveCalls += 1;
      if (saveCalls == 1) throw Exception('disk full');
    });
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const SamRockPairingResponse(success: true));
    when(
      () => applyWalletBehaviorDefaults.execute(
        walletId: any(named: 'walletId'),
        hideOnHome: any(named: 'hideOnHome'),
        autoSweepEnabled: any(named: 'autoSweepEnabled'),
      ),
    ).thenAnswer((_) async {});

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

  test(
    'records BTCPay keychain entries before descriptor submission',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      final events = <String>[];
      late KeychainManifestReservedDerivationRequest capturedRequest;
      when(() => keychainManifest.recordReservedDerivation(any())).thenAnswer((
        invocation,
      ) async {
        events.add('manifest');
        capturedRequest =
            invocation.positionalArguments.single
                as KeychainManifestReservedDerivationRequest;
        return _recordedKeychainEntries;
      });
      when(
        () => keychainManifest.deleteInsertedMaterializations(any()),
      ).thenAnswer((_) async {});
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => deterministicWallets.rollbackCreatedWallets(preparedWallets),
      ).thenAnswer((_) async {});
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {
        events.add('submit');
        return const SamRockPairingResponse(success: true);
      });
      when(
        () => connectionRepository.saveConnection(any()),
      ).thenAnswer((_) async {});
      when(
        () => applyWalletBehaviorDefaults.execute(
          walletId: any(named: 'walletId'),
          hideOnHome: any(named: 'hideOnHome'),
          autoSweepEnabled: any(named: 'autoSweepEnabled'),
        ),
      ).thenAnswer((_) async {});

      await usecase.execute(pairingUrl: pairingUrl);

      expect(events, ['manifest', 'submit']);
      final request = capturedRequest;
      expect(request.reservationId, 'btcpay_wallet_seed');
      expect(request.parentFingerprint, 'fedcba98');
      final materializations = request.materializations
          .cast<KeychainManifestWalletMaterializationRequest>();
      expect(
        materializations.map((materialization) => materialization.walletId),
        [Network.bitcoinMainnet.name, Network.liquidMainnet.name],
      );
      expect(
        materializations.every(
          (materialization) =>
              materialization.childSeedFingerprint == '0123abcd',
        ),
        isTrue,
      );
      expect(
        materializations.map((materialization) => materialization.network),
        [Network.bitcoinMainnet, Network.liquidMainnet],
      );
      expect(
        materializations.map(
          (materialization) => materialization.walletPurpose,
        ),
        [BtcpayWalletNetwork.bitcoin.name, BtcpayWalletNetwork.liquid.name],
      );
      expect(
        materializations.every(
          (materialization) => materialization.scriptType == ScriptType.bip84,
        ),
        isTrue,
      );
    },
  );

  test('rolls back created wallets when manifest recording fails', () async {
    final deterministicWallets = _MockDeterministicWalletsFacade();
    final getSettings = _MockGetSettingsUsecase();
    final pairingService = _MockSamRockPairingServicePort();
    final connectionRepository = _MockBtcpayConnectionRepository();
    final applyWalletBehaviorDefaults =
        _MockApplyWalletBehaviorDefaultsUsecase();
    final keychainManifest = _MockKeychainManifestFacade();
    final preparedWallets = PreparedDeterministicWallets(
      wallets: [
        _wallet(
          specId: BtcpayWalletConstants.bitcoinSpecId,
          network: Network.bitcoinMainnet,
          externalDescriptor: 'btc-desc',
          created: true,
        ),
        _wallet(
          specId: BtcpayWalletConstants.liquidSpecId,
          network: Network.liquidMainnet,
          externalDescriptor: 'lbtc-desc',
          created: true,
        ),
      ],
      parentFingerprint: 'fedcba98',
      childSeedFingerprint: '0123abcd',
      childSeedStoredDuringAttempt: true,
    );
    final usecase = CompleteBtcpaySamRockPairingUsecase(
      getSettings: getSettings,
      parser: const SamRockPairingRequestParser(),
      deterministicWallets: deterministicWallets,
      pairingService: pairingService,
      connectionRepository: connectionRepository,
      applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
      bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
    );
    when(
      () => keychainManifest.recordReservedDerivation(any()),
    ).thenThrow(Exception('manifest write failed'));
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
  });

  test(
    'applies BTCPay wallet behavior defaults after server accepts',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      _stubKeychainManifest(keychainManifest);
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
      );
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(
        () => connectionRepository.saveConnection(any()),
      ).thenAnswer((_) async {});
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const SamRockPairingResponse(success: true));
      when(
        () => applyWalletBehaviorDefaults.execute(
          walletId: any(named: 'walletId'),
          hideOnHome: any(named: 'hideOnHome'),
          autoSweepEnabled: any(named: 'autoSweepEnabled'),
        ),
      ).thenAnswer((_) async {});

      await usecase.execute(pairingUrl: pairingUrl);

      verify(
        () => applyWalletBehaviorDefaults.execute(
          walletId: Network.bitcoinMainnet.name,
          hideOnHome: false,
          autoSweepEnabled: false,
        ),
      ).called(1);
      verify(
        () => applyWalletBehaviorDefaults.execute(
          walletId: Network.liquidMainnet.name,
          hideOnHome: true,
          autoSweepEnabled: true,
        ),
      ).called(1);
    },
  );

  test(
    'completes pairing as paired when defaults application fails',
    () async {
      final deterministicWallets = _MockDeterministicWalletsFacade();
      final getSettings = _MockGetSettingsUsecase();
      final pairingService = _MockSamRockPairingServicePort();
      final connectionRepository = _MockBtcpayConnectionRepository();
      final applyWalletBehaviorDefaults =
          _MockApplyWalletBehaviorDefaultsUsecase();
      final keychainManifest = _MockKeychainManifestFacade();
      _stubKeychainManifest(keychainManifest);
      final preparedWallets = PreparedDeterministicWallets(
        wallets: [
          _wallet(
            specId: BtcpayWalletConstants.bitcoinSpecId,
            network: Network.bitcoinMainnet,
            externalDescriptor: 'btc-desc',
            created: true,
          ),
          _wallet(
            specId: BtcpayWalletConstants.liquidSpecId,
            network: Network.liquidMainnet,
            externalDescriptor: 'lbtc-desc',
            created: true,
          ),
        ],
        parentFingerprint: 'fedcba98',
        childSeedFingerprint: '0123abcd',
        childSeedStoredDuringAttempt: true,
      );
      final usecase = CompleteBtcpaySamRockPairingUsecase(
        getSettings: getSettings,
        parser: const SamRockPairingRequestParser(),
        deterministicWallets: deterministicWallets,
        pairingService: pairingService,
        connectionRepository: connectionRepository,
        applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
        bip85Registry: const Bip85RegistryFacade(),
        keychainManifest: keychainManifest,
      );
      final savedConnections = <BtcpayConnection>[];
      when(() => getSettings.execute()).thenAnswer((_) async => settings);
      when(
        () => deterministicWallets.prepare(any()),
      ).thenAnswer((_) async => preparedWallets);
      when(() => connectionRepository.saveConnection(any())).thenAnswer((
        invocation,
      ) async {
        savedConnections.add(
          invocation.positionalArguments.single as BtcpayConnection,
        );
      });
      when(
        () => pairingService.submitSetup(
          request: any(named: 'request'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async => const SamRockPairingResponse(success: true));
      when(
        () => applyWalletBehaviorDefaults.execute(
          walletId: any(named: 'walletId'),
          hideOnHome: any(named: 'hideOnHome'),
          autoSweepEnabled: any(named: 'autoSweepEnabled'),
        ),
      ).thenThrow(Exception('metadata store unavailable'));

      final connection = await usecase.execute(pairingUrl: pairingUrl);

      expect(connection.isPaired, isTrue);
      expect(savedConnections, hasLength(1));
      expect(savedConnections.single.status, BtcpayConnectionStatus.paired);
    },
  );

  test('prepares BTCPay wallets from the registry reservation', () async {
    final deterministicWallets = _MockDeterministicWalletsFacade();
    final getSettings = _MockGetSettingsUsecase();
    final pairingService = _MockSamRockPairingServicePort();
    final connectionRepository = _MockBtcpayConnectionRepository();
    final applyWalletBehaviorDefaults =
        _MockApplyWalletBehaviorDefaultsUsecase();
    final keychainManifest = _MockKeychainManifestFacade();
    _stubKeychainManifest(keychainManifest);
    final preparedWallets = PreparedDeterministicWallets(
      wallets: [
        _wallet(
          specId: BtcpayWalletConstants.bitcoinSpecId,
          network: Network.bitcoinMainnet,
          externalDescriptor: 'btc-desc',
          created: false,
        ),
        _wallet(
          specId: BtcpayWalletConstants.liquidSpecId,
          network: Network.liquidMainnet,
          externalDescriptor: 'lbtc-desc',
          created: false,
        ),
      ],
      parentFingerprint: 'fedcba98',
      childSeedFingerprint: '0123abcd',
      childSeedStoredDuringAttempt: false,
    );
    final capturedRequests = <DeterministicWalletsRequest>[];
    final usecase = CompleteBtcpaySamRockPairingUsecase(
      getSettings: getSettings,
      parser: const SamRockPairingRequestParser(),
      deterministicWallets: deterministicWallets,
      pairingService: pairingService,
      connectionRepository: connectionRepository,
      applyWalletBehaviorDefaults: applyWalletBehaviorDefaults,
      bip85Registry: const Bip85RegistryFacade(),
      keychainManifest: keychainManifest,
    );
    when(() => getSettings.execute()).thenAnswer((_) async => settings);
    when(() => deterministicWallets.prepare(any())).thenAnswer((invocation) {
      capturedRequests.add(invocation.positionalArguments.single);
      return Future.value(preparedWallets);
    });
    when(
      () => pairingService.submitSetup(
        request: any(named: 'request'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const SamRockPairingResponse(success: true));
    when(() => connectionRepository.saveConnection(any())).thenAnswer((_) async {});
    when(
      () => applyWalletBehaviorDefaults.execute(
        walletId: any(named: 'walletId'),
        hideOnHome: any(named: 'hideOnHome'),
        autoSweepEnabled: any(named: 'autoSweepEnabled'),
      ),
    ).thenAnswer((_) async {});

    await usecase.execute(pairingUrl: pairingUrl);

    expect(capturedRequests, hasLength(1));
    final request = capturedRequests.single;
    expect(
      request.bip85Index,
      const Bip85RegistryFacade().btcpayWalletSeed.walletIndex,
    );
    expect(request.bip85Index, 100);
    expect(request.bip85Alias, 'BTCPay');
    expect(request.walletSpecs.map((spec) => spec.id), [
      BtcpayWalletConstants.bitcoinSpecId,
      BtcpayWalletConstants.liquidSpecId,
    ]);
  });
}

void _stubKeychainManifest(_MockKeychainManifestFacade keychainManifest) {
  when(
    () => keychainManifest.recordReservedDerivation(any()),
  ).thenAnswer((_) async => _recordedKeychainEntries);
  when(
    () => keychainManifest.deleteInsertedMaterializations(any()),
  ).thenAnswer((_) async {});
}

const _recordedKeychainEntries =
    KeychainManifestRecordReservedDerivationResult.forTesting(
      insertedMaterializations: [
        KeychainManifestRecordedMaterialization.walletForTesting(
          entryId: "fedcba98:39'/0'/12'/100'",
          walletId: 'bitcoinMainnet',
        ),
        KeychainManifestRecordedMaterialization.walletForTesting(
          entryId: "fedcba98:39'/0'/12'/100'",
          walletId: 'liquidMainnet',
        ),
      ],
    );

PreparedDeterministicWallet _wallet({
  required String specId,
  required Network network,
  required String externalDescriptor,
  required bool created,
}) {
  return PreparedDeterministicWallet(
    specId: specId,
    walletId: network.name,
    network: network,
    scriptType: ScriptType.bip84,
    label: network.name,
    externalPublicDescriptor: externalDescriptor,
    internalPublicDescriptor: 'internal-desc',
    created: created,
  );
}
