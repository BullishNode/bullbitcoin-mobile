import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/data/settings_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/import_wallet_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSeedRepository extends Mock implements SeedRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockWalletRepository extends Mock implements WalletRepository {}

void main() {
  test('mnemonic wallet import allows non-reserved wallet labels', () async {
    final seedRepository = _MockSeedRepository();
    final settingsRepository = _MockSettingsRepository();
    final walletRepository = _MockWalletRepository();
    final seed =
        Seed.mnemonic(
              mnemonicWords: const ['abandon'],
              bytes: Uint8List(32),
              masterFingerprint: 'fingerprint',
            )
            as MnemonicSeed;
    final wallet = Wallet(
      origin: 'wallet',
      label: 'BTCPay Savings',
      network: Network.bitcoinMainnet,
      xpubFingerprint: 'fingerprint',
      scriptType: ScriptType.bip84,
      xpub: 'xpub',
      externalPublicDescriptor: 'wpkh(xpub/0/*)',
      internalPublicDescriptor: 'wpkh(xpub/1/*)',
      signer: SignerEntity.local,
      signerDevice: null,
      balanceSat: BigInt.zero,
    );
    final usecase = ImportWalletUsecase(
      seedRepository: seedRepository,
      settingsRepository: settingsRepository,
      walletRepository: walletRepository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ['System Wallet'],
      ),
    );

    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'USD',
      ),
    );
    when(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: any(named: 'mnemonicWords'),
        passphrase: any(named: 'passphrase'),
      ),
    ).thenAnswer((_) async => seed);
    when(
      () => walletRepository.createWallet(
        seed: seed,
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'BTCPay Savings',
      ),
    ).thenAnswer((_) async => wallet);

    final result = await usecase.execute(
      mnemonicWords: const ['abandon'],
      label: 'BTCPay Savings',
    );

    expect(result, wallet);
    verify(
      () => walletRepository.createWallet(
        seed: seed,
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'BTCPay Savings',
      ),
    ).called(1);
  });

  test('mnemonic wallet import rejects reserved wallet labels', () async {
    final seedRepository = _MockSeedRepository();
    final settingsRepository = _MockSettingsRepository();
    final walletRepository = _MockWalletRepository();
    final usecase = ImportWalletUsecase(
      seedRepository: seedRepository,
      settingsRepository: settingsRepository,
      walletRepository: walletRepository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ['System Wallet'],
      ),
    );

    await expectLater(
      usecase.execute(mnemonicWords: const ['abandon'], label: 'system wallet'),
      throwsA(isA<ReservedWalletLabelException>()),
    );
    verifyNever(() => settingsRepository.fetch());
    verifyNever(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: any(named: 'mnemonicWords'),
        passphrase: any(named: 'passphrase'),
      ),
    );
  });

  test('mnemonic wallet import wraps async wallet creation errors', () async {
    final seedRepository = _MockSeedRepository();
    final settingsRepository = _MockSettingsRepository();
    final walletRepository = _MockWalletRepository();
    final seed =
        Seed.mnemonic(
              mnemonicWords: const ['abandon'],
              bytes: Uint8List(32),
              masterFingerprint: 'fingerprint',
            )
            as MnemonicSeed;
    final usecase = ImportWalletUsecase(
      seedRepository: seedRepository,
      settingsRepository: settingsRepository,
      walletRepository: walletRepository,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ['System Wallet'],
      ),
    );

    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'USD',
      ),
    );
    when(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: any(named: 'mnemonicWords'),
        passphrase: any(named: 'passphrase'),
      ),
    ).thenAnswer((_) async => seed);
    when(
      () => walletRepository.createWallet(
        seed: seed,
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'Savings',
      ),
    ).thenAnswer((_) async => throw StateError('repository failed'));

    await expectLater(
      usecase.execute(mnemonicWords: const ['abandon'], label: 'Savings'),
      throwsA(isA<ImportWalletException>()),
    );
  });
}
