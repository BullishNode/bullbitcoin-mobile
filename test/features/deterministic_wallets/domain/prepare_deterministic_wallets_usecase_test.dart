import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/domain/bip85_errors.dart';
import 'package:bb_mobile/core/bip85/domain/derive_bip85_mnemonic_at_index_from_default_wallet_usecase.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/seed/domain/seed_failure.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/utils/uint_8_list_x.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/deterministic_wallets_error.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/prepare_deterministic_wallets_usecase.dart';
import 'package:bb_mobile/features/deterministic_wallets/domain/repositories/deterministic_wallet_repository.dart';
import 'package:bip32_keys/bip32_keys.dart' as bip32;
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase extends Mock
    implements DeriveBip85MnemonicAtIndexFromDefaultWalletUsecase {}

class _MockDeterministicWalletRepository extends Mock
    implements DeterministicWalletRepository {}

const _bitcoinSpecId = 'product-bitcoin';
const _liquidSpecId = 'product-liquid';

void main() {
  final mnemonic = bip39.Mnemonic.fromWords(
    words: List.generate(11, (index) => 'zoo') + ['wrong'],
  );
  final childSeed = _seedFromMnemonic(mnemonic);

  late _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase deriveBip85;
  late _MockDeterministicWalletRepository walletRepository;
  late PrepareDeterministicWalletsUsecase usecase;
  late PreparedDeterministicWallet bitcoinWallet;
  late PreparedDeterministicWallet liquidWallet;
  late DeterministicWalletsRequest request;

  setUpAll(() {
    registerFallbackValue(_seedFromMnemonic(mnemonic));
    registerFallbackValue(
      const DeterministicWalletSpec(
        id: _bitcoinSpecId,
        network: Network.bitcoinMainnet,
        scriptType: ScriptType.bip84,
        label: 'Product Bitcoin',
        isDefault: false,
        sync: false,
      ),
    );
  });

  setUp(() async {
    deriveBip85 = _MockDeriveBip85MnemonicAtIndexFromDefaultWalletUsecase();
    walletRepository = _MockDeterministicWalletRepository();
    usecase = PrepareDeterministicWalletsUsecase(
      deriveBip85: deriveBip85,
      walletRepository: walletRepository,
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

    bitcoinWallet = _preparedWallet(
      specId: _bitcoinSpecId,
      walletId: 'wpkh([${childSeed.masterFingerprint}/84h/0h/0h])',
      network: Network.bitcoinMainnet,
      label: 'Product Bitcoin',
      externalDescriptor: 'btc-desc',
      internalDescriptor: 'btc-change-desc',
    );
    liquidWallet = _preparedWallet(
      specId: _liquidSpecId,
      walletId: 'elwpkh([${childSeed.masterFingerprint}/84h/1776h/0h])',
      network: Network.liquidMainnet,
      label: 'Product Liquid',
      externalDescriptor: 'lbtc-desc',
      internalDescriptor: 'lbtc-desc',
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
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.childSeedExists(childSeed.masterFingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => walletRepository.storeChildSeed(any()),
    ).thenAnswer((_) async => childSeed);
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => bitcoinWallet.copyWithCreated(true));
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => liquidWallet.copyWithCreated(true));

    final result = await usecase.execute(request);

    expect(_wallet(result, _bitcoinSpecId).walletId, bitcoinWallet.walletId);
    expect(_wallet(result, _liquidSpecId).walletId, liquidWallet.walletId);
    expect(result.wallets.every((wallet) => wallet.created), isTrue);
    expect(result.shouldDeleteChildSeedOnRollback, isTrue);
    when(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.deleteWallet(liquidWallet.walletId),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).thenAnswer((_) async => const Ok(null));
    await usecase.rollbackCreatedWallets(result);
    verify(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).called(1);
    verify(() => walletRepository.storeChildSeed(any())).called(1);
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
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => bitcoinWallet);
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => liquidWallet);

    final result = await usecase.execute(request);

    expect(_wallet(result, _bitcoinSpecId).walletId, bitcoinWallet.walletId);
    expect(_wallet(result, _liquidSpecId).walletId, liquidWallet.walletId);
    expect(result.wallets.every((wallet) => wallet.created), isFalse);
    expect(result.shouldDeleteChildSeedOnRollback, isFalse);
    verifyNever(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: any(named: 'spec'),
      ),
    );
  });

  test('maps BIP85 derivation conflicts to the feature error family', () async {
    when(
      () => deriveBip85.execute(
        index: 77,
        alias: 'Test Product',
        environment: Environment.mainnet,
      ),
    ).thenThrow(
      Bip85DerivationConflictException(
        'BIP85 derivation already exists with a different alias',
      ),
    );

    await expectLater(
      usecase.execute(request),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.derivationConflict,
        ),
      ),
    );
  });

  test('rejects wallet ID collisions with unexpected descriptors', () async {
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenThrow(
      DeterministicWalletException.walletMismatch(
        'Existing deterministic wallet metadata does not match expected '
        'descriptors for $_bitcoinSpecId',
      ),
    );

    expect(
      () => usecase.execute(request),
      throwsA(isA<DeterministicWalletException>()),
    );
  });

  test('reports rollback failure when automatic cleanup fails', () async {
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.childSeedExists(childSeed.masterFingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => walletRepository.storeChildSeed(any()),
    ).thenAnswer((_) async => childSeed);
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => bitcoinWallet.copyWithCreated(true));
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.last,
      ),
    ).thenThrow(Exception('create failed'));
    when(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).thenThrow(Exception('delete failed'));
    when(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).thenAnswer((_) async => const Ok(null));

    await expectLater(
      usecase.execute(request),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.rollbackFailed,
        ),
      ),
    );

    verify(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).called(1);
    verifyNever(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    );
  });

  test('deletes child seed when automatic cleanup succeeds', () async {
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.childSeedExists(childSeed.masterFingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => walletRepository.storeChildSeed(any()),
    ).thenAnswer((_) async => childSeed);
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => bitcoinWallet.copyWithCreated(true));
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.last,
      ),
    ).thenThrow(Exception('create failed'));
    when(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).thenAnswer((_) async => const Ok(null));

    await expectLater(usecase.execute(request), throwsA(isA<Exception>()));

    verify(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).called(1);
    verify(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).called(1);
  });

  test('surfaces rollback failure when child seed delete fails', () async {
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.getMatchingWallet(
        seedPreview: any(named: 'seedPreview'),
        spec: request.walletSpecs.last,
      ),
    ).thenAnswer((_) async => null);
    when(
      () => walletRepository.childSeedExists(childSeed.masterFingerprint),
    ).thenAnswer((_) async => false);
    when(
      () => walletRepository.storeChildSeed(any()),
    ).thenAnswer((_) async => childSeed);
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.first,
      ),
    ).thenAnswer((_) async => bitcoinWallet.copyWithCreated(true));
    when(
      () => walletRepository.createWallet(
        childSeed: any(named: 'childSeed'),
        spec: request.walletSpecs.last,
      ),
    ).thenThrow(Exception('create failed'));
    when(
      () => walletRepository.deleteWallet(bitcoinWallet.walletId),
    ).thenAnswer((_) async {});
    when(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).thenAnswer((_) async => Err(SeedDeleteFailure('secure storage locked')));

    // A failing child-seed delete must be surfaced as rollbackFailed, not
    // silently swallowed as a successful cleanup.
    await expectLater(
      usecase.execute(request),
      throwsA(
        isA<DeterministicWalletException>().having(
          (error) => error.type,
          'type',
          DeterministicWalletExceptionType.rollbackFailed,
        ),
      ),
    );

    verify(
      () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
    ).called(1);
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

  test(
    'keeps child seed when explicit rollback wallet cleanup fails',
    () async {
      final result = PreparedDeterministicWallets(
        wallets: [
          bitcoinWallet.copyWithCreated(true),
          liquidWallet.copyWithCreated(true),
        ],
        childSeedFingerprint: childSeed.masterFingerprint,
        childSeedStoredDuringAttempt: true,
      );
      when(
        () => walletRepository.deleteWallet(bitcoinWallet.walletId),
      ).thenThrow(Exception('delete failed'));
      when(
        () => walletRepository.deleteWallet(liquidWallet.walletId),
      ).thenAnswer((_) async {});
      when(
        () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
      ).thenAnswer((_) async => const Ok(null));

      await expectLater(
        usecase.rollbackCreatedWallets(result),
        throwsA(
          isA<DeterministicWalletException>().having(
            (error) => error.type,
            'type',
            DeterministicWalletExceptionType.rollbackFailed,
          ),
        ),
      );

      verify(
        () => walletRepository.deleteWallet(bitcoinWallet.walletId),
      ).called(1);
      verify(
        () => walletRepository.deleteWallet(liquidWallet.walletId),
      ).called(1);
      verifyNever(
        () => walletRepository.deleteChildSeed(childSeed.masterFingerprint),
      );
    },
  );
}

PreparedDeterministicWallet _wallet(
  PreparedDeterministicWallets result,
  String specId,
) {
  return result.wallets.firstWhere((prepared) => prepared.specId == specId);
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

PreparedDeterministicWallet _preparedWallet({
  required String specId,
  required String walletId,
  required Network network,
  required String? label,
  required String externalDescriptor,
  required String internalDescriptor,
}) {
  return PreparedDeterministicWallet(
    specId: specId,
    walletId: walletId,
    network: network,
    scriptType: ScriptType.bip84,
    label: label,
    externalPublicDescriptor: externalDescriptor,
    internalPublicDescriptor: internalDescriptor,
    created: false,
  );
}

extension on PreparedDeterministicWallet {
  PreparedDeterministicWallet copyWithCreated(bool created) {
    return PreparedDeterministicWallet(
      specId: specId,
      walletId: walletId,
      network: network,
      scriptType: scriptType,
      label: label,
      externalPublicDescriptor: externalPublicDescriptor,
      internalPublicDescriptor: internalPublicDescriptor,
      created: created,
    );
  }
}
