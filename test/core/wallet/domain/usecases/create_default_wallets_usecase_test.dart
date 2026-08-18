import 'dart:typed_data';

import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/data/services/mnemonic_generator.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/inconsistent_wallet_state_exception.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockMnemonicGenerator extends Mock implements MnemonicGenerator {}

class _MockWallet extends Mock implements Wallet {}

void main() {
  const fingerprint = 'f00dbabe';
  final mnemonic = List<String>.filled(12, 'abandon');

  late _MockSeedRepository seedRepository;
  late _MockSettingsRepository settingsRepository;
  late _MockWalletRepository walletRepository;
  late _MockMnemonicGenerator mnemonicGenerator;
  late CreateDefaultWalletsUsecase usecase;

  _MockWallet walletStub(Network network) {
    final wallet = _MockWallet();
    when(() => wallet.network).thenReturn(network);
    when(() => wallet.masterFingerprint).thenReturn(fingerprint);
    return wallet;
  }

  setUp(() {
    seedRepository = _MockSeedRepository();
    settingsRepository = _MockSettingsRepository();
    walletRepository = _MockWalletRepository();
    mnemonicGenerator = _MockMnemonicGenerator();
    usecase = CreateDefaultWalletsUsecase(
      seedRepository: seedRepository,
      settingsRepository: settingsRepository,
      mnemonicGenerator: mnemonicGenerator,
      walletRepository: walletRepository,
    );

    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    final existing = [
      walletStub(Network.bitcoinMainnet),
      walletStub(Network.liquidMainnet),
    ];
    when(
      () => walletRepository.getWallets(
        onlyDefaults: true,
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) async => existing);
  });

  test('reuses the existing defaults when their seed is still there', () async {
    when(
      () => seedRepository.exists(fingerprint),
    ).thenAnswer((_) async => true);

    final wallets = await usecase.execute();

    expect(wallets, hasLength(2));
    verify(() => seedRepository.exists(fingerprint)).called(1);
    // No wallet was created: the records were reused as they are.
    verify(
      () => walletRepository.getWallets(
        onlyDefaults: true,
        environment: Environment.mainnet,
      ),
    ).called(1);
    verifyNoMoreInteractions(walletRepository);
  });

  test('throws the typed inconsistent state when the seed store has no seed '
      'for the existing records', () async {
    when(
      () => seedRepository.exists(fingerprint),
    ).thenAnswer((_) async => false);

    await expectLater(
      usecase.execute(),
      throwsA(
        isA<InconsistentWalletStateException>().having(
          (e) => e.fingerprint,
          'fingerprint',
          fingerprint,
        ),
      ),
    );
  });

  test('stores the seed back instead of failing when the caller restores the '
      'very mnemonic those records came from', () async {
    when(
      () => seedRepository.exists(fingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => seedRepository.fingerprintFor(
        mnemonicWords: mnemonic,
        passphrase: null,
      ),
    ).thenReturn(fingerprint);
    when(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: mnemonic,
        passphrase: null,
      ),
    ).thenAnswer(
      (_) async => MnemonicSeed(
        mnemonicWords: mnemonic,
        bytes: Uint8List(64),
        masterFingerprint: fingerprint,
      ),
    );

    final wallets = await usecase.execute(mnemonicWords: mnemonic);

    expect(wallets, hasLength(2));
    verify(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: mnemonic,
        passphrase: null,
      ),
    ).called(1);
  });

  test('still fails when the restored mnemonic is not the one the records were '
      'built from', () async {
    when(
      () => seedRepository.exists(fingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => seedRepository.fingerprintFor(
        mnemonicWords: mnemonic,
        passphrase: null,
      ),
    ).thenReturn('deadbeef');

    await expectLater(
      usecase.execute(mnemonicWords: mnemonic),
      throwsA(isA<InconsistentWalletStateException>()),
    );
    verifyNever(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: any(named: 'mnemonicWords'),
        passphrase: any(named: 'passphrase'),
      ),
    );
  });
}
