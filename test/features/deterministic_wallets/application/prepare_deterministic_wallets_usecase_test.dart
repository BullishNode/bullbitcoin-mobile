import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/domain/derive_bip85_mnemonic_at_index_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/data/repository/seed_repository.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/storage/tables/wallet_metadata_table.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/data/models/wallet_metadata_model.dart';
import 'package:bb_mobile/core/wallet/data/repositories/wallet_repository.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/deterministic_wallets/application/application_errors.dart';
import 'package:bb_mobile/features/deterministic_wallets/application/prepare_deterministic_wallets_usecase.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase extends Mock
    implements DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase {}

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSeedRepository extends Mock implements SeedRepository {}

const _testMasterFingerprint = '0123abcd';
const _bitcoinSpecId = 'product-bitcoin';
const _liquidSpecId = 'product-liquid';

void main() {
  final mnemonic = bip39.Mnemonic.fromWords(
    words: List.generate(11, (index) => 'zoo') + ['wrong'],
  );
  final childSeed = _seedFromMnemonic(mnemonic);

  late _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase deriveBip85;
  late _MockWalletRepository walletRepository;
  late _MockSeedRepository seedRepository;
  late PrepareDeterministicWalletsUsecase usecase;
  late WalletMetadataModel bitcoinMetadata;
  late WalletMetadataModel liquidMetadata;
  late Wallet bitcoinWallet;
  late Wallet liquidWallet;
  late DeterministicWalletsRequest request;

  setUpAll(() {
    registerFallbackValue(_seedFromMnemonic(mnemonic));
  });

  setUp(() async {
    deriveBip85 = _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase();
    walletRepository = _MockWalletRepository();
    seedRepository = _MockSeedRepository();
    usecase = PrepareDeterministicWalletsUsecase(
      deriveBip85: deriveBip85,
      walletRepository: walletRepository,
      seedRepository: seedRepository,
      deriveWalletMetadata: _deriveMetadata,
    );
    request = const DeterministicWalletsRequest(
      bip85Index: 77,
      bip85Alias: 'Test Product',
      environment: Environment.mainnet,
      walletSpecs: [
        DeterministicWalletSpec(
          id: _bitcoinSpecId,
          network: Network.bitcoinMainnet,
          scriptType: ScriptType.bip84,
          label: 'Product Bitcoin',
          isDefault: false,
          sync: false,
        ),
        DeterministicWalletSpec(
          id: _liquidSpecId,
          network: Network.liquidMainnet,
          scriptType: ScriptType.bip84,
          label: 'Product Liquid',
          isDefault: false,
          sync: false,
        ),
      ],
    );

    bitcoinMetadata = _metadata(
      id: 'wpkh([$_testMasterFingerprint/84h/0h/0h])',
      network: Network.bitcoinMainnet,
      label: 'Product Bitcoin',
      externalDescriptor: 'btc-desc',
      internalDescriptor: 'btc-change-desc',
    );
    liquidMetadata = _metadata(
      id: 'elwpkh([$_testMasterFingerprint/84h/1776h/0h])',
      network: Network.liquidMainnet,
      label: 'Product Liquid',
      externalDescriptor: 'lbtc-desc',
      internalDescriptor: 'lbtc-desc',
    );
    bitcoinWallet = _walletFromMetadata(
      bitcoinMetadata,
      network: Network.bitcoinMainnet,
    );
    liquidWallet = _walletFromMetadata(
      liquidMetadata,
      network: Network.liquidMainnet,
    );

    when(
      () => deriveBip85.execute(
        index: 77,
        alias: 'Test Product',
        environment: Environment.mainnet,
      ),
    ).thenAnswer(
      (_) async => (derivation: "39'/0'/12'/77'", mnemonic: mnemonic),
    );
  });

  test('creates requested wallets from a reserved BIP85 index', () async {
    when(
      () => walletRepository.getWallet(bitcoinMetadata.id),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.getWallet(liquidMetadata.id),
    ).thenAnswer((_) async => null);
    when(
      () => seedRepository.exists(childSeed.masterFingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: childSeed.mnemonicWords,
        passphrase: childSeed.passphrase,
      ),
    ).thenAnswer((_) async => childSeed);
    when(
      () => walletRepository.createWallet(
        seed: any(named: 'seed'),
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'Product Bitcoin',
      ),
    ).thenAnswer((_) async => bitcoinWallet);
    when(
      () => walletRepository.createWallet(
        seed: any(named: 'seed'),
        network: Network.liquidMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'Product Liquid',
      ),
    ).thenAnswer((_) async => liquidWallet);

    final result = await usecase.execute(request);

    expect(_wallet(result, _bitcoinSpecId).id, bitcoinWallet.id);
    expect(_wallet(result, _liquidSpecId).id, liquidWallet.id);
    expect(result.wallets.every((wallet) => wallet.created), isTrue);
    expect(result.shouldDeleteChildSeedOnRollback, isTrue);
    when(
      () => walletRepository.deleteWallet(walletId: bitcoinWallet.id),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.deleteWallet(walletId: liquidWallet.id),
    ).thenAnswer((_) async {});
    when(
      () => seedRepository.delete(childSeed.masterFingerprint),
    ).thenAnswer((_) async {});
    await usecase.rollbackCreatedWallets(result);
    verify(() => seedRepository.delete(childSeed.masterFingerprint)).called(1);
    verify(
      () => seedRepository.createFromMnemonic(
        mnemonicWords: childSeed.mnemonicWords,
        passphrase: childSeed.passphrase,
      ),
    ).called(1);
    verify(
      () => deriveBip85.execute(
        index: 77,
        alias: 'Test Product',
        environment: Environment.mainnet,
      ),
    ).called(1);
  });

  test('reuses existing wallets when expected descriptors match', () async {
    when(
      () => walletRepository.getWallet(bitcoinMetadata.id),
    ).thenAnswer((_) async => bitcoinWallet);
    when(
      () => walletRepository.getWallet(liquidMetadata.id),
    ).thenAnswer((_) async => liquidWallet);

    final result = await usecase.execute(request);

    expect(_wallet(result, _bitcoinSpecId).id, bitcoinWallet.id);
    expect(_wallet(result, _liquidSpecId).id, liquidWallet.id);
    expect(result.wallets.every((wallet) => wallet.created), isFalse);
    expect(result.shouldDeleteChildSeedOnRollback, isFalse);
    verifyNever(
      () => walletRepository.createWallet(
        seed: any(named: 'seed'),
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'Product Bitcoin',
      ),
    );
    verifyNever(
      () => walletRepository.createWallet(
        seed: any(named: 'seed'),
        network: Network.liquidMainnet,
        scriptType: ScriptType.bip84,
        isDefault: false,
        sync: false,
        label: 'Product Liquid',
      ),
    );
  });

  test('rejects wallet ID collisions with unexpected descriptors', () async {
    when(() => walletRepository.getWallet(bitcoinMetadata.id)).thenAnswer(
      (_) async => bitcoinWallet.copyWith(externalPublicDescriptor: 'wrong'),
    );

    expect(
      () => usecase.execute(request),
      throwsA(isA<DeterministicWalletException>()),
    );
  });

  test('rejects empty wallet specs', () async {
    final invalidRequest = DeterministicWalletsRequest(
      bip85Index: request.bip85Index,
      bip85Alias: request.bip85Alias,
      environment: request.environment,
      walletSpecs: const [],
    );

    expect(
      () => usecase.execute(invalidRequest),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.invalidRequest,
        ),
      ),
    );
  });

  test('rejects duplicate wallet spec IDs', () async {
    final invalidRequest = DeterministicWalletsRequest(
      bip85Index: request.bip85Index,
      bip85Alias: request.bip85Alias,
      environment: request.environment,
      walletSpecs: [request.walletSpecs.first, request.walletSpecs.first],
    );

    expect(
      () => usecase.execute(invalidRequest),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.invalidRequest,
        ),
      ),
    );
  });
}

Wallet _wallet(PreparedDeterministicWallets result, String specId) {
  return result.wallets
      .firstWhere((prepared) => prepared.specId == specId)
      .wallet;
}

Future<WalletMetadataModel> _deriveMetadata({
  required Seed seed,
  required Network network,
  required ScriptType scriptType,
  String? label,
  required bool isDefault,
}) async {
  if (network.isBitcoin) {
    return _metadata(
      id: 'wpkh([$_testMasterFingerprint/84h/0h/0h])',
      network: network,
      label: label,
      externalDescriptor: 'btc-desc',
      internalDescriptor: 'btc-change-desc',
    );
  }

  return _metadata(
    id: 'elwpkh([$_testMasterFingerprint/84h/1776h/0h])',
    network: network,
    label: label,
    externalDescriptor: 'lbtc-desc',
    internalDescriptor: 'lbtc-desc',
  );
}

WalletMetadataModel _metadata({
  required String id,
  required Network network,
  required String? label,
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
    label: label,
  );
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

Wallet _walletFromMetadata(
  WalletMetadataModel metadata, {
  required Network network,
}) {
  return Wallet(
    origin: metadata.id,
    label: metadata.label,
    network: network,
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
