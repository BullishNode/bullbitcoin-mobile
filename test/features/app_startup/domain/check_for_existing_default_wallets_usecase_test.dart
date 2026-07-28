import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/inconsistent_wallet_state_exception.dart';
import 'package:bb_mobile/features/app_startup/domain/usecases/check_for_existing_default_wallets_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockWallet extends Mock implements Wallet {}

void main() {
  const fingerprint = 'f00dbabe';

  late _MockSeedRepository seedRepository;
  late _MockSettingsRepository settingsRepository;
  late _MockWalletRepository walletRepository;
  late CheckForExistingDefaultWalletsUsecase usecase;

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
    usecase = CheckForExistingDefaultWalletsUsecase(
      settingsRepository: settingsRepository,
      walletRepository: walletRepository,
      seedRepository: seedRepository,
    );

    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    final defaults = [
      walletStub(Network.bitcoinMainnet),
      walletStub(Network.liquidMainnet),
    ];
    when(
      () => walletRepository.getWallets(
        onlyDefaults: true,
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) async => defaults);
  });

  test('reports the defaults as usable when their seed is present', () async {
    when(
      () => seedRepository.exists(fingerprint),
    ).thenAnswer((_) async => true);

    expect(await usecase.execute(), isTrue);
    // Presence check only: the seed itself is never read at cold start.
    verifyNever(() => seedRepository.get(any()));
  });

  test('throws the typed inconsistent state when the seed store lost the seed '
      'of surviving wallet records', () async {
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

  test('reports a fresh install without touching the seed store', () async {
    when(
      () => walletRepository.getWallets(
        onlyDefaults: true,
        environment: Environment.mainnet,
      ),
    ).thenAnswer((_) async => const []);

    expect(await usecase.execute(), isFalse);
    verifyZeroInteractions(seedRepository);
  });
}
