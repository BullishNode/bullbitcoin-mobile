import 'package:bb_mobile/core/bip85/domain/bip85_derivation_entity.dart';
import 'package:bb_mobile/core/bip85/domain/fetch_all_derivations_usecase.dart';
import 'package:bb_mobile/core/settings/domain/repositories/settings_repository.dart';
import 'package:bb_mobile/core/settings/domain/settings_entity.dart';
import 'package:bb_mobile/core/wallet/domain/wallet_label_reservations.dart';
import 'package:bb_mobile/features/external_receive_wallets/reserved_external_receive_wallet_labels.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/create_manual_bip85_wallets_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_wallet_manifest_origins_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_origin.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_restore_result.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/public/create_manual_bip85_wallets.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDeriveRootKey extends Mock
    implements DeriveWalletManifestRootKeyUsecase {}

class _MockFetchOrigins extends Mock
    implements FetchWalletManifestOriginsUsecase {}

class _MockRestoreSnapshot extends Mock
    implements RestoreWalletManifestSnapshotUsecase {}

class _MockPublishLocalManifest extends Mock
    implements PublishLocalWalletManifestUsecase {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockFetchAllBip85Derivations extends Mock
    implements FetchAllBip85DerivationsUsecase {}

const _rootFingerprint = '73c5da0a';

void main() {
  late _MockDeriveRootKey deriveRootKey;
  late _MockFetchOrigins fetchOrigins;
  late _MockRestoreSnapshot restoreSnapshot;
  late _MockPublishLocalManifest publishLocalManifest;
  late _MockSettingsRepository settingsRepository;
  late _MockFetchAllBip85Derivations fetchAllBip85Derivations;
  late CreateManualBip85WalletsUsecase usecase;

  setUpAll(() {
    registerFallbackValue(
      WalletManifestSnapshot(createdAt: 0, accounts: const []),
    );
  });

  setUp(() {
    deriveRootKey = _MockDeriveRootKey();
    fetchOrigins = _MockFetchOrigins();
    restoreSnapshot = _MockRestoreSnapshot();
    publishLocalManifest = _MockPublishLocalManifest();
    settingsRepository = _MockSettingsRepository();
    fetchAllBip85Derivations = _MockFetchAllBip85Derivations();
    usecase = CreateManualBip85WalletsUsecase(
      deriveRootKey: deriveRootKey,
      fetchOrigins: fetchOrigins,
      restoreSnapshot: restoreSnapshot,
      publishLocalManifest: publishLocalManifest,
      settingsRepository: settingsRepository,
      fetchAllBip85Derivations: fetchAllBip85Derivations,
      walletLabelReservationPolicy: const WalletLabelReservationPolicy(
        reservedLabels: ReservedExternalReceiveWalletLabel.userReserved,
      ),
    );

    when(() => deriveRootKey.execute()).thenAnswer(
      (_) async => const WalletManifestRootKeyContext(
        xprvBase58: 'xprv',
        rootFingerprint: _rootFingerprint,
      ),
    );
    when(() => fetchOrigins.execute()).thenAnswer((_) async => const []);
    when(
      () => fetchAllBip85Derivations.execute(usage: any(named: 'usage')),
    ).thenAnswer((_) async => const []);
    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.mainnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );
    when(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    ).thenAnswer((invocation) async {
      final snapshot =
          invocation.namedArguments[#snapshot] as WalletManifestSnapshot;
      return WalletManifestSnapshotRestoreResult(
        outcomes: [
          for (final account in snapshot.accounts)
            WalletManifestAccountRestoreOutcome(
              account: account,
              status: WalletManifestRestoreStatus.created,
              walletId: '${account.network.value}-wallet',
              actualLabel: account.name,
            ),
        ],
      );
    });
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 1);
  });

  test(
    'creates a manual Liquid BIP85 wallet and publishes the manifest',
    () async {
      final result = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          liquidLabel: 'My Liquid Wallet',
        ),
      );

      expect(result.index, 0);
      expect(result.manifestPublishFailed, isFalse);
      expect(result.wallets.single.network, WalletManifestNetwork.liquid);
      expect(result.wallets.single.walletId, 'liquid-wallet');
      expect(result.wallets.single.label, 'My Liquid Wallet');

      final captured =
          verify(
                () => restoreSnapshot.execute(
                  snapshot: captureAny(named: 'snapshot'),
                ),
              ).captured.single
              as WalletManifestSnapshot;
      expect(captured.accounts, hasLength(1));
      expect(captured.accounts.single.name, 'My Liquid Wallet');
      expect(captured.accounts.single.network, WalletManifestNetwork.liquid);
      expect(captured.accounts.single.bip85DerivationPath.index, 0);
      verify(() => publishLocalManifest.execute()).called(1);
    },
  );

  test(
    'creates Bitcoin and Liquid wallets at the same index for both',
    () async {
      final result = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.both,
          bitcoinLabel: 'Savings BTC',
          liquidLabel: 'Savings LBTC',
        ),
      );

      expect(result.index, 0);
      expect(result.wallets.map((wallet) => wallet.network), [
        WalletManifestNetwork.bitcoin,
        WalletManifestNetwork.liquid,
      ]);
      final captured =
          verify(
                () => restoreSnapshot.execute(
                  snapshot: captureAny(named: 'snapshot'),
                ),
              ).captured.single
              as WalletManifestSnapshot;
      expect(captured.accounts.map((account) => account.bip85Index).toSet(), {
        0,
      });
    },
  );

  test(
    'auto-index skips used selected network identities independently',
    () async {
      when(() => fetchOrigins.execute()).thenAnswer(
        (_) async => [
          _origin(index: 0, network: WalletManifestNetwork.bitcoin),
        ],
      );

      final bitcoin = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.bitcoin,
          bitcoinLabel: 'Next BTC',
        ),
      );
      final liquid = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          liquidLabel: 'First LBTC',
        ),
      );

      expect(bitcoin.index, 1);
      expect(liquid.index, 0);
    },
  );

  test('auto-index for both skips when either network side is used', () async {
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [_origin(index: 0, network: WalletManifestNetwork.liquid)],
    );

    final result = await usecase.execute(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.both,
        bitcoinLabel: 'Next BTC',
        liquidLabel: 'Next LBTC',
      ),
    );

    expect(result.index, 1);
  });

  test('manual creation blocks reserved indexes', () async {
    await expectLater(
      usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.bitcoin,
          index: 75,
          bitcoinLabel: 'Reserved',
        ),
      ),
      throwsA(isA<WalletManifestManualBip85IndexUnavailableException>()),
    );

    verifyNever(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    );
  });

  test('manual creation blocks existing selected identities', () async {
    when(() => fetchOrigins.execute()).thenAnswer(
      (_) async => [_origin(index: 3, network: WalletManifestNetwork.liquid)],
    );

    await expectLater(
      usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          index: 3,
          liquidLabel: 'Duplicate',
        ),
      ),
      throwsA(isA<WalletManifestManualBip85IndexUnavailableException>()),
    );

    verifyNever(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    );
  });

  test('manual creation blocks reserved labels before restore', () async {
    await expectLater(
      usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          liquidLabel:
              ReservedExternalReceiveWalletLabel.lightningAddressLiquid,
        ),
      ),
      throwsA(isA<WalletManifestManualBip85ReservedLabelException>()),
    );

    verifyNever(() => deriveRootKey.execute());
    verifyNever(() => fetchOrigins.execute());
    verifyNever(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    );
  });

  test(
    'manual creation blocks existing BIP85 derivation indexes before restore',
    () async {
      when(
        () => fetchAllBip85Derivations.execute(usage: any(named: 'usage')),
      ).thenAnswer(
        (_) async => [
          Bip85DerivationEntity(
            path: Bip85DerivationPath.mnemonic12(index: 3).value,
            xprvFingerprint: _rootFingerprint,
            alias: 'Existing',
            status: Bip85Status.active,
            usage: Bip85Usage.manual,
            application: Bip85Application.bip39,
            index: 3,
          ),
        ],
      );

      await expectLater(
        usecase.execute(
          const CreateManualBip85WalletsCommand(
            networkSelection: ManualBip85WalletNetworkSelection.liquid,
            index: 3,
            liquidLabel: 'Duplicate',
          ),
        ),
        throwsA(isA<WalletManifestManualBip85IndexUnavailableException>()),
      );

      verifyNever(
        () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
      );
    },
  );

  test('auto-index skips existing BIP85 derivation indexes', () async {
    when(
      () => fetchAllBip85Derivations.execute(usage: any(named: 'usage')),
    ).thenAnswer(
      (_) async => [
        Bip85DerivationEntity(
          path: Bip85DerivationPath.mnemonic12(index: 0).value,
          xprvFingerprint: _rootFingerprint,
          alias: 'Existing',
          status: Bip85Status.active,
          usage: Bip85Usage.manual,
          application: Bip85Application.bip39,
          index: 0,
        ),
      ],
    );

    final result = await usecase.execute(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.liquid,
        liquidLabel: 'Next',
      ),
    );

    expect(result.index, 1);
  });

  test('uses testnet manifest networks in testnet environment', () async {
    when(() => settingsRepository.fetch()).thenAnswer(
      (_) async => const SettingsEntity(
        environment: Environment.testnet,
        bitcoinUnit: BitcoinUnit.sats,
        currencyCode: 'CAD',
      ),
    );

    await usecase.execute(
      const CreateManualBip85WalletsCommand(
        networkSelection: ManualBip85WalletNetworkSelection.both,
        bitcoinLabel: 'Test BTC',
        liquidLabel: 'Test LBTC',
      ),
    );

    final captured =
        verify(
              () => restoreSnapshot.execute(
                snapshot: captureAny(named: 'snapshot'),
              ),
            ).captured.single
            as WalletManifestSnapshot;
    expect(captured.accounts.map((account) => account.network), [
      WalletManifestNetwork.testnet3,
      WalletManifestNetwork.liquidTestnet,
    ]);
  });

  test(
    'returns a non-fatal publish failure flag after local creation',
    () async {
      when(() => publishLocalManifest.execute()).thenThrow(Exception('relay'));

      final result = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          liquidLabel: 'Created Locally',
        ),
      );

      expect(result.manifestPublishFailed, isTrue);
      expect(result.wallets.single.walletId, 'liquid-wallet');
    },
  );

  test(
    'returns created wallets when a both-network creation partially fails',
    () async {
      when(
        () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
      ).thenAnswer((invocation) async {
        final snapshot =
            invocation.namedArguments[#snapshot] as WalletManifestSnapshot;
        return WalletManifestSnapshotRestoreResult(
          outcomes: [
            WalletManifestAccountRestoreOutcome(
              account: snapshot.accounts.first,
              status: WalletManifestRestoreStatus.created,
              walletId: 'bitcoin-wallet',
              actualLabel: snapshot.accounts.first.name,
            ),
            WalletManifestAccountRestoreOutcome(
              account: snapshot.accounts.last,
              status: WalletManifestRestoreStatus.failed,
              failureStage: WalletManifestRestoreFailureStage.createWallet,
              cause: Exception('liquid failed'),
            ),
          ],
        );
      });

      final result = await usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.both,
          bitcoinLabel: 'Partial BTC',
          liquidLabel: 'Partial LBTC',
        ),
      );

      expect(result.wallets, hasLength(1));
      expect(result.wallets.single.network, WalletManifestNetwork.bitcoin);
      expect(result.partialFailure, isTrue);
      verify(() => publishLocalManifest.execute()).called(1);
    },
  );

  test('requires labels for selected networks', () async {
    await expectLater(
      usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.both,
          bitcoinLabel: 'BTC Only',
        ),
      ),
      throwsA(isA<WalletManifestManualBip85LabelRequiredException>()),
    );

    verifyNever(() => deriveRootKey.execute());
    verifyNever(() => fetchOrigins.execute());
    verifyNever(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    );
  });

  test('fails if wallet creation does not return all wallet ids', () async {
    when(
      () => restoreSnapshot.execute(snapshot: any(named: 'snapshot')),
    ).thenAnswer((invocation) async {
      final snapshot =
          invocation.namedArguments[#snapshot] as WalletManifestSnapshot;
      return WalletManifestSnapshotRestoreResult(
        outcomes: [
          WalletManifestAccountRestoreOutcome(
            account: snapshot.accounts.single,
            status: WalletManifestRestoreStatus.created,
          ),
        ],
      );
    });

    await expectLater(
      usecase.execute(
        const CreateManualBip85WalletsCommand(
          networkSelection: ManualBip85WalletNetworkSelection.liquid,
          liquidLabel: 'Broken',
        ),
      ),
      throwsA(isA<WalletManifestManualBip85WalletCreationException>()),
    );

    verifyNever(() => publishLocalManifest.execute());
  });
}

WalletManifestOrigin _origin({
  required int index,
  required WalletManifestNetwork network,
}) {
  return WalletManifestOrigin(
    walletId: '${network.value}-$index',
    rootFingerprint: _rootFingerprint,
    bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: index),
    network: network,
    createdAt: 1,
    updatedAt: 1,
  );
}
