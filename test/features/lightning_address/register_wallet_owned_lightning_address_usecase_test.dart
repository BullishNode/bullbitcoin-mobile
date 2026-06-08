import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/get_settings_usecase.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/bullnym/bullnym_locator.dart';
import 'package:bb_mobile/features/bullnym/public/bullnym_facade.dart';
import 'package:bb_mobile/features/deterministic_wallets/public/deterministic_wallets_facade.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/lightning_address/application/ports/lightning_address_default_wallet_xprv_port.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/delete_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/lookup_wallet_owned_lightning_address_registration_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/prepare_lightning_address_wallet_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/domain/usecases/register_wallet_owned_lightning_address_usecase.dart';
import 'package:bb_mobile/features/lightning_address/frameworks/default_wallet_xprv_adapter.dart';
import 'package:bb_mobile/features/lightning_address/lightning_address_locator.dart';
import 'package:bb_mobile/features/lightning_address/public/lightning_address_facade.dart';
import 'package:bb_mobile/features/nostr_identity/nostr_identity_locator.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:get_it/get_it.dart';
import 'package:test/test.dart';

void main() {
  group('RegisterWalletOwnedLightningAddressUsecase', () {
    late _FakeDefaultWalletXprvPort defaultWalletXprv;
    late _FakePrepareLightningAddressWalletUsecase prepareWallet;
    late _FakeRegisterLightningAddressUsecase register;
    late RegisterWalletOwnedLightningAddressUsecase usecase;

    setUp(() {
      defaultWalletXprv = _FakeDefaultWalletXprvPort();
      prepareWallet = _FakePrepareLightningAddressWalletUsecase();
      register = _FakeRegisterLightningAddressUsecase();
      usecase = RegisterWalletOwnedLightningAddressUsecase(
        defaultWalletXprv: defaultWalletXprv,
        prepareWallet: prepareWallet,
        register: register,
      );
    });

    test(
      'derives xprv, prepares wallet, and registers with descriptor',
      () async {
        final result = await usecase.execute(
          const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
        );

        expect(defaultWalletXprv.deriveCalls, 1);
        expect(prepareWallet.executeCalls, 1);
        expect(register.commands.single.xprvBase58, 'xprv');
        expect(register.commands.single.nym, 'alice');
        expect(register.commands.single.ctDescriptor, 'ct-desc');
        expect(result.registration.nym, 'alice');
        expect(result.registration.lightningAddress, 'alice@example.invalid');
        expect(result.walletId, 'la-wallet');
        expect(result.walletCreated, true);
      },
    );

    test(
      'rejects blank nym before secret, wallet, or network side effects',
      () {
        expect(
          () => usecase.execute(
            const RegisterWalletOwnedLightningAddressCommand(nym: '  '),
          ),
          throwsA(
            isA<LightningAddressException>().having(
              (e) => e.kind,
              'kind',
              LightningAddressErrorKind.invalidNym,
            ),
          ),
        );
        expect(defaultWalletXprv.deriveCalls, 0);
        expect(prepareWallet.executeCalls, 0);
        expect(register.commands, isEmpty);
      },
    );

    test(
      'maps default-wallet xprv failures before wallet preparation',
      () async {
        defaultWalletXprv.error = StateError('no default wallet');

        await expectLater(
          usecase.execute(
            const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
          ),
          throwsA(
            isA<WalletOwnedLightningAddressRegistrationException>()
                .having(
                  (e) => e.phase,
                  'phase',
                  WalletOwnedLightningAddressRegistrationFailurePhase
                      .localPreparation,
                )
                .having(
                  (e) => e.cause.kind,
                  'kind',
                  LightningAddressErrorKind.localPreparationFailed,
                )
                .having((e) => e.cause.retryable, 'retryable', true),
          ),
        );
        expect(prepareWallet.executeCalls, 0);
        expect(register.commands, isEmpty);
      },
    );

    test('does not register when wallet preparation fails', () async {
      prepareWallet.error = LightningAddressException.localPreparationFailed(
        code: 'ManifestFailed',
        retryable: true,
      );

      await expectLater(
        usecase.execute(
          const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
        ),
        throwsA(
          isA<WalletOwnedLightningAddressRegistrationException>()
              .having(
                (e) => e.phase,
                'phase',
                WalletOwnedLightningAddressRegistrationFailurePhase
                    .localPreparation,
              )
              .having(
                (e) => e.cause.kind,
                'kind',
                LightningAddressErrorKind.localPreparationFailed,
              ),
        ),
      );
      expect(register.commands, isEmpty);
    });

    test('keeps prepared wallet boundary when registration fails', () async {
      register.error = const LightningAddressTimeoutException(
        code: 'Timeout',
        retryable: true,
      );

      await expectLater(
        usecase.execute(
          const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
        ),
        throwsA(
          isA<WalletOwnedLightningAddressRegistrationException>()
              .having(
                (e) => e.phase,
                'phase',
                WalletOwnedLightningAddressRegistrationFailurePhase
                    .registrationSubmission,
              )
              .having((e) => e.walletId, 'walletId', 'la-wallet')
              .having((e) => e.walletCreated, 'walletCreated', true)
              .having(
                (e) => e.descriptorMayHaveBeenSubmitted,
                'descriptorMayHaveBeenSubmitted',
                true,
              )
              .having(
                (e) => e.submissionMayBeUncertain,
                'submissionMayBeUncertain',
                true,
              )
              .having(
                (e) => e.cause.kind,
                'kind',
                LightningAddressErrorKind.timeout,
              ),
        ),
      );
      expect(prepareWallet.executeCalls, 1);
      expect(register.commands.single.ctDescriptor, 'ct-desc');
    });

    test('reports reused wallet metadata for idempotent retry', () async {
      prepareWallet.prepared = _prepared(created: false);

      final result = await usecase.execute(
        const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
      );

      expect(result.walletId, 'la-wallet');
      expect(result.walletCreated, false);
    });
  });

  group('LookupWalletOwnedLightningAddressRegistrationUsecase', () {
    late _FakeDefaultWalletXprvPort defaultWalletXprv;
    late _FakeLookupLightningAddressRegistrationUsecase lookupRegistration;
    late _FakeNostrIdentityFacade nostrIdentity;
    late LookupWalletOwnedLightningAddressRegistrationUsecase usecase;

    setUp(() {
      defaultWalletXprv = _FakeDefaultWalletXprvPort();
      lookupRegistration = _FakeLookupLightningAddressRegistrationUsecase();
      nostrIdentity = _FakeNostrIdentityFacade();
      usecase = LookupWalletOwnedLightningAddressRegistrationUsecase(
        defaultWalletXprv: defaultWalletXprv,
        lookupRegistration: lookupRegistration,
        nostrIdentity: nostrIdentity,
      );
    });

    test('derives xprv internally and returns Bullnym status', () async {
      final result = await usecase.execute();

      expect(defaultWalletXprv.deriveCalls, 1);
      expect(nostrIdentity.xprvs.single, 'xprv');
      expect(lookupRegistration.executeCalls, 1);
      expect(lookupRegistration.npubHex, 'npubhex');
      expect(result.nym, 'alice');
      expect(result.active, true);
    });

    test('maps default-wallet xprv failures before lookup', () async {
      defaultWalletXprv.error = StateError('no default wallet');

      await expectLater(
        usecase.execute(),
        throwsA(
          isA<LightningAddressException>().having(
            (e) => e.kind,
            'kind',
            LightningAddressErrorKind.localPreparationFailed,
          ),
        ),
      );
      expect(lookupRegistration.executeCalls, 0);
    });
  });

  test('LightningAddressFacade delegates wallet-owned registration', () async {
    final walletOwned = _FakeRegisterWalletOwnedLightningAddressUsecase();
    final lookupWalletOwned =
        _FakeLookupWalletOwnedLightningAddressRegistrationUsecase();
    final facade = LightningAddressFacade.forUsecases(
      prepareWallet: _FakePrepareLightningAddressWalletUsecase(),
      register: _FakeRegisterLightningAddressUsecase(),
      deleteRegistration: _FakeDeleteLightningAddressRegistrationUsecase(),
      lookupRegistration: _FakeLookupLightningAddressRegistrationUsecase(),
      registerWalletOwned: walletOwned,
      lookupWalletOwnedRegistration: lookupWalletOwned,
    );

    final result = await facade.registerWalletOwned(
      const RegisterWalletOwnedLightningAddressCommand(nym: 'alice'),
    );

    expect(walletOwned.commands.single.nym, 'alice');
    expect(result.registration.lightningAddress, 'alice@example.invalid');
  });

  test('LightningAddressFacade delegates wallet-owned lookup', () async {
    final lookupWalletOwned =
        _FakeLookupWalletOwnedLightningAddressRegistrationUsecase();
    final facade = LightningAddressFacade.forUsecases(
      prepareWallet: _FakePrepareLightningAddressWalletUsecase(),
      register: _FakeRegisterLightningAddressUsecase(),
      deleteRegistration: _FakeDeleteLightningAddressRegistrationUsecase(),
      lookupRegistration: _FakeLookupLightningAddressRegistrationUsecase(),
      registerWalletOwned: _FakeRegisterWalletOwnedLightningAddressUsecase(),
      lookupWalletOwnedRegistration: lookupWalletOwned,
    );

    final result = await facade.lookupWalletOwnedRegistration();

    expect(lookupWalletOwned.executeCalls, 1);
    expect(result.nym, 'alice');
    expect(result.active, true);
  });

  test(
    'DefaultWalletXprvAdapter derives from the actual default wallet network',
    () async {
      final seed = _zeroMnemonicSeed();
      final walletRepository = _FakeWalletRepository([
        _wallet('default-bitcoin', network: Network.bitcoinTestnet),
      ]);
      final seedRepository = _FakeSeedRepository(seed);
      final adapter = DefaultWalletXprvAdapter(
        walletRepository: walletRepository,
        seedRepository: seedRepository,
      );

      final xprv = await adapter.deriveDefaultWalletXprv();

      expect(walletRepository.onlyDefaults, true);
      expect(walletRepository.onlyBitcoin, true);
      expect(seedRepository.fingerprints.single, 'child-fp');
      expect(xprv, startsWith('tprv'));
    },
  );

  test('feature locators resolve the headless Lightning Address facade', () {
    final getIt = GetIt.asNewInstance();
    getIt.registerFactory<WalletRepository>(
      () => _FakeWalletRepository([
        _wallet('default-bitcoin', network: Network.bitcoinMainnet),
      ]),
    );
    getIt.registerFactory<SeedRepository>(
      () => _FakeSeedRepository(_zeroMnemonicSeed()),
    );
    getIt.registerFactory<GetSettingsUsecase>(() => _FakeGetSettingsUsecase());
    getIt.registerFactory<DeterministicWalletsFacade>(
      () => _FakeDeterministicWalletsFacade(),
    );
    getIt.registerFactory<KeychainManifestFacade>(
      () => _FakeKeychainManifestFacade(),
    );

    BullnymLocator.setup(getIt);
    NostrIdentityLocator.setup(getIt);
    LightningAddressLocator.setup(getIt);

    expect(getIt<BullnymFacade>(), isA<BullnymFacade>());
    expect(getIt<NostrIdentityFacade>(), isA<NostrIdentityFacade>());
    expect(getIt<LightningAddressFacade>(), isA<LightningAddressFacade>());
  });
}

class _FakeDefaultWalletXprvPort
    implements LightningAddressDefaultWalletXprvPort {
  int deriveCalls = 0;
  Object? error;

  @override
  Future<String> deriveDefaultWalletXprv() async {
    deriveCalls += 1;
    final error = this.error;
    if (error != null) throw error;
    return 'xprv';
  }
}

class _FakePrepareLightningAddressWalletUsecase
    implements PrepareLightningAddressWalletUsecase {
  int executeCalls = 0;
  PreparedLightningAddressWallet prepared = _prepared();
  LightningAddressException? error;

  @override
  Future<PreparedLightningAddressWallet> execute() async {
    executeCalls += 1;
    final error = this.error;
    if (error != null) throw error;
    return prepared;
  }
}

class _FakeRegisterLightningAddressUsecase
    implements RegisterLightningAddressUsecase {
  final commands = <({String xprvBase58, String nym, String ctDescriptor})>[];
  LightningAddressException? error;

  @override
  Future<LightningAddressRegistration> execute({
    required String xprvBase58,
    required String nym,
    required String ctDescriptor,
  }) async {
    commands.add((xprvBase58: xprvBase58, nym: nym, ctDescriptor: ctDescriptor));
    final error = this.error;
    if (error != null) throw error;
    return LightningAddressRegistration(
      nym: nym,
      lightningAddress: '$nym@example.invalid',
    );
  }
}

class _FakeRegisterWalletOwnedLightningAddressUsecase
    implements RegisterWalletOwnedLightningAddressUsecase {
  final commands = <RegisterWalletOwnedLightningAddressCommand>[];

  @override
  Future<WalletOwnedLightningAddressRegistration> execute(
    RegisterWalletOwnedLightningAddressCommand command,
  ) async {
    commands.add(command);
    return WalletOwnedLightningAddressRegistration(
      registration: LightningAddressRegistration(
        nym: command.nym,
        lightningAddress: '${command.nym}@example.invalid',
      ),
      walletId: 'la-wallet',
      walletCreated: true,
    );
  }
}

class _FakeLookupLightningAddressRegistrationUsecase
    implements LookupLightningAddressRegistrationUsecase {
  int executeCalls = 0;
  String? npubHex;

  @override
  Future<LightningAddressStatus> execute({required String npubHex}) async {
    executeCalls += 1;
    this.npubHex = npubHex;
    return const LightningAddressStatus(nym: 'alice', active: true);
  }
}

class _FakeDeleteLightningAddressRegistrationUsecase
    implements DeleteLightningAddressRegistrationUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNostrIdentityFacade extends NostrIdentityFacade {
  final xprvs = <String>[];

  @override
  String deriveBullnymServerAuthPublicKeyFromXprv(String xprvBase58) {
    xprvs.add(xprvBase58);
    return 'npubhex';
  }
}

class _FakeLookupWalletOwnedLightningAddressRegistrationUsecase
    implements LookupWalletOwnedLightningAddressRegistrationUsecase {
  int executeCalls = 0;

  @override
  Future<LightningAddressStatus> execute() async {
    executeCalls += 1;
    return const LightningAddressStatus(nym: 'alice', active: true);
  }
}

class _FakeWalletRepository implements WalletRepository {
  final List<Wallet> wallets;
  bool? onlyDefaults;
  bool? onlyBitcoin;

  _FakeWalletRepository(this.wallets);

  @override
  Future<List<Wallet>> getWallets({
    Environment? environment,
    bool? onlyDefaults,
    bool? onlyBitcoin,
    bool? onlyLiquid,
    bool sync = false,
  }) async {
    this.onlyDefaults = onlyDefaults;
    this.onlyBitcoin = onlyBitcoin;
    return wallets;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSeedRepository implements SeedRepository {
  final Seed seed;
  final fingerprints = <String>[];

  _FakeSeedRepository(this.seed);

  @override
  Future<Seed> get(String fingerprint) async {
    fingerprints.add(fingerprint);
    return seed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGetSettingsUsecase implements GetSettingsUsecase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeterministicWalletsFacade implements DeterministicWalletsFacade {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeKeychainManifestFacade implements KeychainManifestFacade {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PreparedLightningAddressWallet _prepared({bool created = true}) {
  return PreparedLightningAddressWallet(
    walletId: 'la-wallet',
    ctDescriptor: 'ct-desc',
    created: created,
  );
}

Wallet _wallet(String id, {Network network = Network.liquidMainnet}) {
  return Wallet(
    origin: id,
    network: network,
    masterFingerprint: 'child-fp',
    xpubFingerprint: 'child-fp',
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'ct-desc',
    internalPublicDescriptor: 'internal',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

Seed _zeroMnemonicSeed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    bip39.Language.english,
  );
  return Seed.mnemonic(
    mnemonicWords: mnemonic.words,
    bytes: Uint8List.fromList(mnemonic.seed),
    masterFingerprint: 'parent-fp',
  );
}
