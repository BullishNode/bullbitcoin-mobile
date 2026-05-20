import 'dart:typed_data';

import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/entities/signer_entity.dart';
import 'package:bb_mobile/core/seed/domain/entity/seed.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_wallet_operations_port.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/record_wallet_manifest_origin_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_restore_result.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletOperations extends Mock
    implements WalletManifestWalletOperationsPort {}

class _MockFetchOrigins extends Mock
    implements FetchWalletManifestOriginsUsecase {}

class _MockRecordOrigin extends Mock
    implements RecordWalletManifestOriginUsecase {}

class _MockDeriveRootKey extends Mock
    implements DeriveWalletManifestRootKeyUsecase {}

const _zeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _childMnemonic =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';
const _rootFingerprint = '73c5da0a';
const _childFingerprint = 'aabbccdd';

void main() {
  late _MockWalletOperations walletOperations;
  late _MockFetchOrigins fetchOrigins;
  late _MockRecordOrigin recordOrigin;
  late _MockDeriveRootKey deriveRootKey;
  late RestoreWalletManifestSnapshotUsecase usecase;

  setUpAll(() {
    registerFallbackValue(_seed());
    registerFallbackValue(WalletManifestNetwork.liquid);
    registerFallbackValue(Network.liquidMainnet);
    registerFallbackValue(ScriptType.bip84);
    registerFallbackValue(bip39.MnemonicLength.words12);
    registerFallbackValue(Bip85Usage.manual);
  });

  setUp(() {
    walletOperations = _MockWalletOperations();
    fetchOrigins = _MockFetchOrigins();
    recordOrigin = _MockRecordOrigin();
    deriveRootKey = _MockDeriveRootKey();
    usecase = RestoreWalletManifestSnapshotUsecase(
      walletOperations: walletOperations,
      fetchOrigins: fetchOrigins,
      recordOrigin: recordOrigin,
      deriveRootKey: deriveRootKey,
    );

    when(() => deriveRootKey.execute()).thenAnswer(
      (_) async => WalletManifestRootKeyContext(
        xprvBase58: _zeroMnemonicXprv(),
        rootFingerprint: _rootFingerprint,
      ),
    );
    when(() => fetchOrigins.execute()).thenAnswer((_) async => const []);
    when(
      () => walletOperations.getWallets(sync: false),
    ).thenAnswer((_) async => const []);
    when(
      () => recordOrigin.execute(
        walletId: any(named: 'walletId'),
        network: any(named: 'network'),
        rootFingerprint: any(named: 'rootFingerprint'),
        bip85DerivationPath: any(named: 'bip85DerivationPath'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => walletOperations.deleteWallet(walletId: any(named: 'walletId')),
    ).thenAnswer((_) async {});
    when(
      () => walletOperations.deleteMnemonicDerivation(
        xprvBase58: any(named: 'xprvBase58'),
        derivationPath: any(named: 'derivationPath'),
      ),
    ).thenAnswer((_) async {});
  });

  test(
    'maps root key derivation failures before reading local state',
    () async {
      when(
        () => deriveRootKey.execute(),
      ).thenThrow(WalletManifestKeyDerivationException('missing root key'));

      await expectLater(
        usecase.execute(
          snapshot: WalletManifestSnapshot(createdAt: 1, accounts: const []),
        ),
        throwsA(
          isA<WalletManifestSnapshotRestoreException>().having(
            (e) => e.cause,
            'cause',
            isA<WalletManifestKeyDerivationException>(),
          ),
        ),
      );

      verifyNever(() => fetchOrigins.execute());
      verifyNever(() => walletOperations.getWallets(sync: false));
    },
  );

  test(
    'restores manifest accounts without syncing and records origins',
    () async {
      final account = _account(index: 76, name: 'Payment Page-LBTC');
      _stubRestore(
        walletOperations: walletOperations,
        account: account,
        wallet: _wallet('payment-page'),
      );

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored.map((outcome) => outcome.account), [account]);
      expect(result.restored.single.walletId, 'payment-page');
      expect(result.restored.single.actualLabel, 'Payment Page-LBTC');
      expect(result.restored.single.walletStateChanged, isFalse);
      expect(result.alreadyPresent, isEmpty);
      expect(result.skipped, isEmpty);
      expect(result.failed, isEmpty);
      verify(() => deriveRootKey.execute()).called(1);
      verify(
        () => walletOperations.deriveMnemonicPreview(
          xprvBase58: _zeroMnemonicXprv(),
          length: bip39.MnemonicLength.words12,
          index: 76,
        ),
      ).called(1);
      verify(
        () => walletOperations.createWallet(
          seed: any(named: 'seed'),
          network: Network.liquidMainnet,
          scriptType: ScriptType.bip84,
          label: 'Payment Page-LBTC',
          sync: false,
        ),
      ).called(1);
      verify(
        () => walletOperations.recordMnemonicDerivation(
          xprvBase58: _zeroMnemonicXprv(),
          derivationPath: "39'/0'/12'/76'",
          alias: 'Payment Page-LBTC',
          usage: Bip85Usage.system,
        ),
      ).called(1);
      verify(
        () => recordOrigin.execute(
          walletId: 'payment-page',
          network: WalletManifestNetwork.liquid,
          rootFingerprint: _rootFingerprint,
          bip85DerivationPath: account.bip85DerivationPath.value,
        ),
      ).called(1);
    },
  );

  test(
    'marks identities already recorded locally as already present',
    () async {
      final account = _account(index: 76, name: 'Payment Page-LBTC');
      final existing = _wallet('existing').copyWith(label: 'Existing Label');
      when(
        () => fetchOrigins.execute(),
      ).thenAnswer((_) async => [_origin(account, walletId: 'existing')]);
      when(
        () => walletOperations.getWallets(sync: false),
      ).thenAnswer((_) async => [existing]);

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored, isEmpty);
      expect(result.alreadyPresent.single.account, account);
      expect(result.alreadyPresent.single.walletId, 'existing');
      expect(result.alreadyPresent.single.actualLabel, 'Existing Label');
      expect(result.alreadyPresent.single.walletStateChanged, isFalse);
      expect(result.skipped, isEmpty);
      expect(result.failed, isEmpty);
      verifyNever(
        () => walletOperations.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: any(named: 'length'),
          index: any(named: 'index'),
        ),
      );
    },
  );

  test('repairs stale origins whose wallet no longer exists', () async {
    final account = _account(index: 76, name: 'Payment Page-LBTC');
    when(
      () => fetchOrigins.execute(),
    ).thenAnswer((_) async => [_origin(account, walletId: 'missing')]);
    _stubRestore(
      walletOperations: walletOperations,
      account: account,
      wallet: _wallet('payment-page'),
    );

    final result = await usecase.execute(
      snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
    );

    expect(result.restored.single.account, account);
    verify(
      () => recordOrigin.execute(
        walletId: 'payment-page',
        network: WalletManifestNetwork.liquid,
        rootFingerprint: _rootFingerprint,
        bip85DerivationPath: account.bip85DerivationPath.value,
      ),
    ).called(1);
  });

  test('isolates per-account restore failures', () async {
    final failing = _account(index: 76, name: 'Payment Page-LBTC');
    final succeeding = _account(index: 77, name: 'BTCPay-LBTC');
    when(
      () => walletOperations.deriveMnemonicPreview(
        xprvBase58: any(named: 'xprvBase58'),
        length: any(named: 'length'),
        index: 76,
      ),
    ).thenThrow(Exception('derive failed'));
    _stubRestore(
      walletOperations: walletOperations,
      account: succeeding,
      wallet: _wallet('btcpay'),
    );

    final result = await usecase.execute(
      snapshot: WalletManifestSnapshot(
        createdAt: 1,
        accounts: [failing, succeeding],
      ),
    );

    expect(result.restored.map((outcome) => outcome.account), [succeeding]);
    expect(result.restored.single.walletStateChanged, isFalse);
    expect(result.failed.single.account, failing);
    expect(
      result.failed.single.failureStage,
      WalletManifestRestoreFailureStage.deriveMnemonic,
    );
    verify(
      () => recordOrigin.execute(
        walletId: 'btcpay',
        network: WalletManifestNetwork.liquid,
        rootFingerprint: _rootFingerprint,
        bip85DerivationPath: succeeding.bip85DerivationPath.value,
      ),
    ).called(1);
  });

  test(
    'skips accounts for a different root fingerprint before derivation',
    () async {
      final account = WalletManifestAccount(
        rootFingerprint: '00000000',
        bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 76),
        network: WalletManifestNetwork.liquid,
        name: 'Payment Page-LBTC',
        timestamp: 1,
      );

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored, isEmpty);
      expect(result.alreadyPresent, isEmpty);
      expect(result.skipped.single.account, account);
      expect(result.failed, isEmpty);
      verifyNever(
        () => walletOperations.deriveMnemonicPreview(
          xprvBase58: any(named: 'xprvBase58'),
          length: any(named: 'length'),
          index: any(named: 'index'),
        ),
      );
      verifyNever(
        () => walletOperations.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
          sync: any(named: 'sync'),
        ),
      );
    },
  );

  test(
    'repairs an exact existing wallet without creating a duplicate',
    () async {
      final account = _account(index: 76, name: 'Payment Page-LBTC');
      final existing = _wallet('existing-payment-page');
      _stubRestore(
        walletOperations: walletOperations,
        account: account,
        wallet: _wallet('unused'),
        existingWallets: [existing],
      );

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored, isEmpty);
      expect(result.alreadyPresent.single.account, account);
      expect(result.alreadyPresent.single.walletId, 'existing-payment-page');
      expect(result.alreadyPresent.single.walletStateChanged, isTrue);
      verifyNever(
        () => walletOperations.createWallet(
          seed: any(named: 'seed'),
          network: any(named: 'network'),
          scriptType: any(named: 'scriptType'),
          label: any(named: 'label'),
          sync: any(named: 'sync'),
        ),
      );
      verify(
        () => recordOrigin.execute(
          walletId: 'existing-payment-page',
          network: WalletManifestNetwork.liquid,
          rootFingerprint: _rootFingerprint,
          bip85DerivationPath: account.bip85DerivationPath.value,
        ),
      ).called(1);
    },
  );

  test(
    'makes fallback labels collision-resistant within restore batch',
    () async {
      final first = _account(index: 78, name: '');
      final second = _account(index: 79, name: 'BIP85 Wallet 78 LBTC');
      _stubRestore(
        walletOperations: walletOperations,
        account: first,
        wallet: _wallet('first').copyWith(label: 'BIP85 Wallet 78 LBTC'),
      );
      _stubRestore(
        walletOperations: walletOperations,
        account: second,
        wallet: _wallet('second').copyWith(label: 'BIP85 Wallet 78 LBTC 2'),
      );

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(
          createdAt: 1,
          accounts: [first, second],
        ),
      );

      expect(result.restored.map((outcome) => outcome.account), [
        first,
        second,
      ]);
      verify(
        () => walletOperations.createWallet(
          seed: any(named: 'seed'),
          network: Network.liquidMainnet,
          scriptType: ScriptType.bip84,
          label: 'BIP85 Wallet 78 LBTC',
          sync: false,
        ),
      ).called(1);
      verify(
        () => walletOperations.createWallet(
          seed: any(named: 'seed'),
          network: Network.liquidMainnet,
          scriptType: ScriptType.bip84,
          label: 'BIP85 Wallet 78 LBTC 2',
          sync: false,
        ),
      ).called(1);
    },
  );

  test(
    'reports origin persistence failures with created wallet details',
    () async {
      final account = _account(index: 76, name: 'Payment Page-LBTC');
      _stubRestore(
        walletOperations: walletOperations,
        account: account,
        wallet: _wallet('payment-page'),
      );
      when(
        () => recordOrigin.execute(
          walletId: any(named: 'walletId'),
          network: any(named: 'network'),
          rootFingerprint: any(named: 'rootFingerprint'),
          bip85DerivationPath: any(named: 'bip85DerivationPath'),
        ),
      ).thenThrow(Exception('origin failed'));

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored, isEmpty);
      expect(result.failed.single.account, account);
      expect(result.failed.single.walletId, 'payment-page');
      expect(result.failed.single.actualLabel, 'Payment Page-LBTC');
      expect(
        result.failed.single.failureStage,
        WalletManifestRestoreFailureStage.recordOrigin,
      );
      verify(
        () => walletOperations.deleteWallet(walletId: 'payment-page'),
      ).called(1);
      verify(
        () => walletOperations.deleteMnemonicDerivation(
          xprvBase58: _zeroMnemonicXprv(),
          derivationPath: "39'/0'/12'/76'",
        ),
      ).called(1);
    },
  );

  test(
    'record BIP85 failure after wallet creation reports local changes',
    () async {
      final account = _account(index: 76, name: 'Payment Page-LBTC');
      _stubRestore(
        walletOperations: walletOperations,
        account: account,
        wallet: _wallet('payment-page'),
      );
      when(
        () => walletOperations.recordMnemonicDerivation(
          xprvBase58: any(named: 'xprvBase58'),
          derivationPath: any(named: 'derivationPath'),
          alias: any(named: 'alias'),
          usage: any(named: 'usage'),
        ),
      ).thenThrow(Exception('bip85 record failed'));

      final result = await usecase.execute(
        snapshot: WalletManifestSnapshot(createdAt: 1, accounts: [account]),
      );

      expect(result.restored, isEmpty);
      expect(result.failed.single.account, account);
      expect(result.failed.single.walletId, 'payment-page');
      expect(
        result.failed.single.failureStage,
        WalletManifestRestoreFailureStage.recordBip85,
      );
      verify(
        () => walletOperations.deleteWallet(walletId: 'payment-page'),
      ).called(1);
      verify(
        () => walletOperations.deleteMnemonicDerivation(
          xprvBase58: _zeroMnemonicXprv(),
          derivationPath: "39'/0'/12'/76'",
        ),
      ).called(1);
    },
  );
}

void _stubRestore({
  required _MockWalletOperations walletOperations,
  required WalletManifestAccount account,
  required Wallet wallet,
  List<Wallet> existingWallets = const [],
}) {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _childMnemonic,
    bip39.Language.english,
  );
  when(
    () => walletOperations.deriveMnemonicPreview(
      xprvBase58: any(named: 'xprvBase58'),
      length: any(named: 'length'),
      index: account.bip85Index,
    ),
  ).thenAnswer(
    (_) async =>
        (derivation: "39'/0'/12'/${account.bip85Index}'", mnemonic: mnemonic),
  );
  when(
    () =>
        walletOperations.createSeedFromMnemonic(mnemonicWords: mnemonic.words),
  ).thenAnswer((_) async => _seed());
  when(
    () => walletOperations.getWallets(sync: false),
  ).thenAnswer((_) async => existingWallets);
  when(
    () => walletOperations.createWallet(
      seed: any(named: 'seed'),
      network: any(named: 'network'),
      scriptType: any(named: 'scriptType'),
      label: any(named: 'label'),
      sync: false,
    ),
  ).thenAnswer((_) async => wallet);
  when(
    () => walletOperations.recordMnemonicDerivation(
      xprvBase58: any(named: 'xprvBase58'),
      derivationPath: "39'/0'/12'/${account.bip85Index}'",
      alias: any(named: 'alias'),
      usage: any(named: 'usage'),
    ),
  ).thenAnswer((_) async {});
}

WalletManifestAccount _account({required int index, required String name}) {
  return WalletManifestAccount(
    rootFingerprint: _rootFingerprint,
    bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: index),
    network: WalletManifestNetwork.liquid,
    name: name,
    timestamp: 1,
  );
}

WalletManifestOrigin _origin(
  WalletManifestAccount account, {
  required String walletId,
}) {
  return WalletManifestOrigin(
    walletId: walletId,
    rootFingerprint: account.rootFingerprint,
    bip85DerivationPath: account.bip85DerivationPath,
    network: account.network,
    createdAt: 1,
    updatedAt: 1,
  );
}

MnemonicSeed _seed() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _childMnemonic,
    bip39.Language.english,
  );
  return Seed.mnemonic(
        mnemonicWords: mnemonic.words,
        bytes: Uint8List.fromList(mnemonic.seed),
        masterFingerprint: _childFingerprint,
      )
      as MnemonicSeed;
}

Wallet _wallet(String id) {
  return Wallet(
    origin: id,
    label: id,
    network: Network.liquidMainnet,
    isDefault: false,
    masterFingerprint: _childFingerprint,
    xpubFingerprint: _childFingerprint,
    scriptType: ScriptType.bip84,
    xpub: 'xpub',
    externalPublicDescriptor: 'ct(slip77(...),elwpkh(xpub/0/*))',
    internalPublicDescriptor: 'ct(slip77(...),elwpkh(xpub/1/*))',
    signer: SignerEntity.local,
    signerDevice: null,
    balanceSat: BigInt.zero,
  );
}

String _zeroMnemonicXprv() {
  final mnemonic = bip39.Mnemonic.fromSentence(
    _zeroMnemonic,
    bip39.Language.english,
  );
  return Bip32Derivation.getXprvFromSeed(
    Uint8List.fromList(mnemonic.seed),
    Network.bitcoinMainnet,
  );
}
