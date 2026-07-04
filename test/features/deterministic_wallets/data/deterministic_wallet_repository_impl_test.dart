import 'dart:typed_data';

import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/storage/tables/wallet_metadata_table.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/deterministic_wallets/data/deterministic_wallet_repository_impl.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

const _spec = DeterministicWalletSpec(
  id: 'product-bitcoin',
  network: Network.bitcoinMainnet,
  scriptType: ScriptType.bip84,
  label: 'Product Bitcoin',
  isDefault: false,
  sync: false,
);

void main() {
  final mnemonic = bip39.Mnemonic.fromWords(
    words: List.generate(11, (index) => 'zoo') + ['wrong'],
  );
  final seed = _seedFromMnemonic(mnemonic);
  final metadata = _metadata(
    id: 'wpkh([${seed.masterFingerprint}/84h/0h/0h])',
    externalDescriptor: 'external-desc',
    internalDescriptor: 'internal-desc',
  );
  final wallet = _walletFromMetadata(metadata);

  late _MockWalletRepository walletRepository;
  late _MockSeedRepository seedRepository;
  late DeterministicWalletRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(seed);
  });

  setUp(() {
    walletRepository = _MockWalletRepository();
    seedRepository = _MockSeedRepository();
    repository = DeterministicWalletRepositoryImpl(
      walletRepository: walletRepository,
      seedRepository: seedRepository,
      deriveWalletMetadata:
          ({
            required Seed seed,
            required Network network,
            required ScriptType scriptType,
            String? label,
            required bool isDefault,
          }) async {
            return metadata;
          },
    );
  });

  test('getMatchingWallet returns null when no wallet exists', () async {
    when(
      () => walletRepository.getWallet(metadata.id),
    ).thenAnswer((_) async => null);

    final result = await repository.getMatchingWallet(
      seedPreview: seed,
      spec: _spec,
    );

    expect(result, isNull);
  });

  test('getMatchingWallet returns narrowed DTO for matching wallet', () async {
    when(
      () => walletRepository.getWallet(metadata.id),
    ).thenAnswer((_) async => wallet);

    final result = await repository.getMatchingWallet(
      seedPreview: seed,
      spec: _spec,
    );

    expect(result, isNotNull);
    expect(result!.specId, _spec.id);
    expect(result.walletId, wallet.id);
    expect(result.network, wallet.network);
    expect(result.scriptType, wallet.scriptType);
    expect(result.label, wallet.label);
    expect(result.externalPublicDescriptor, wallet.externalPublicDescriptor);
    expect(result.internalPublicDescriptor, wallet.internalPublicDescriptor);
    expect(result.created, isFalse);
  });

  test('getMatchingWallet rejects descriptor mismatch', () async {
    when(() => walletRepository.getWallet(metadata.id)).thenAnswer(
      (_) async => wallet.copyWith(externalPublicDescriptor: 'wrong'),
    );

    await expectLater(
      repository.getMatchingWallet(seedPreview: seed, spec: _spec),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.walletMismatch,
        ),
      ),
    );
  });

  test(
    'createWallet delegates core creation and maps created wallet',
    () async {
      when(
        () => walletRepository.createWallet(
          seed: seed,
          network: _spec.network,
          scriptType: _spec.scriptType,
          isDefault: _spec.isDefault,
          sync: _spec.sync,
          label: _spec.label,
        ),
      ).thenAnswer((_) async => wallet);

      final result = await repository.createWallet(
        childSeed: seed,
        spec: _spec,
      );

      expect(result.walletId, wallet.id);
      expect(result.externalPublicDescriptor, wallet.externalPublicDescriptor);
      expect(result.created, isTrue);
    },
  );

  test('delegates seed and wallet cleanup operations', () async {
    when(
      () => seedRepository.exists(seed.masterFingerprint),
    ).thenAnswer((_) async => true);
    when(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: seed.mnemonicWords,
        passphrase: seed.passphrase,
      ),
    ).thenAnswer((_) async => seed);
    when(
      () => seedRepository.delete(seed.masterFingerprint),
    ).thenAnswer((_) async => const Ok(null));
    when(
      () => walletRepository.deleteWallet(walletId: wallet.id),
    ).thenAnswer((_) async {});

    expect(await repository.childSeedExists(seed.masterFingerprint), isTrue);
    expect(await repository.storeChildSeed(seed), seed);
    await repository.deleteChildSeed(seed.masterFingerprint);
    await repository.deleteWallet(wallet.id);

    verify(() => seedRepository.exists(seed.masterFingerprint)).called(1);
    verify(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: seed.mnemonicWords,
        passphrase: seed.passphrase,
      ),
    ).called(1);
    verify(() => seedRepository.delete(seed.masterFingerprint)).called(1);
    verify(() => walletRepository.deleteWallet(walletId: wallet.id)).called(1);
  });
}

MnemonicSeed _seedFromMnemonic(bip39.Mnemonic mnemonic) {
  final seedBytes = Uint8List.fromList(mnemonic.seed);
  return Seed.mnemonic(
        mnemonicWords: mnemonic.words,
        bytes: seedBytes,
        masterFingerprint: bip32.Bip32Keys.fromSeed(
          seedBytes,
        ).fingerprint.toHexString(),
      )
      as MnemonicSeed;
}

WalletMetadataModel _metadata({
  required String id,
  required String externalDescriptor,
  required String internalDescriptor,
}) {
  return WalletMetadataModel(
    id: id,
    masterFingerprint: 'child-fingerprint',
    xpubFingerprint: 'xpub-fingerprint',
    isEncryptedVaultTested: false,
    isPhysicalBackupTested: false,
    xpub: 'xpub',
    externalPublicDescriptor: externalDescriptor,
    internalPublicDescriptor: internalDescriptor,
    signer: Signer.local,
    isDefault: false,
    label: _spec.label,
  );
}

Wallet _walletFromMetadata(WalletMetadataModel metadata) {
  return Wallet(
    origin: metadata.id,
    label: metadata.label,
    network: _spec.network,
    isDefault: metadata.isDefault,
    masterFingerprint: metadata.masterFingerprint,
    xpubFingerprint: metadata.xpubFingerprint,
    scriptType: metadata.scriptType,
    xpub: metadata.xpub,
    externalPublicDescriptor: metadata.externalPublicDescriptor,
    internalPublicDescriptor: metadata.internalPublicDescriptor,
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}
