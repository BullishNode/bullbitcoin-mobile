import 'dart:async';
import 'dart:typed_data';

import 'package:bb_mobile/core/nostr/nostr_keychain_handle.dart';
import 'package:bb_mobile/core/utils/bip32_derivation.dart';
import 'package:bb_mobile/core/wallet/domain/entities/wallet.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_nostr_snapshot_store.dart';
import 'package:bb_mobile/features/wallet_manifest/application/ports/wallet_manifest_file_saver.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/audit_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/build_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/check_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_nostr_handle_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/derive_wallet_manifest_root_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/fetch_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_wallet_manifest_snapshot_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/save_wallet_manifest_payload_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/start_wallet_manifest_restore_after_seed_recovery_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/bip85_derivation_path.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_account.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_network.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_restore_result.dart';
import 'package:bb_mobile/features/wallet_manifest/domain/wallet_manifest_snapshot.dart';
import 'package:bb_mobile/features/wallet_manifest/wallet_manifest_errors.dart';
import 'package:bip39_mnemonic/bip39_mnemonic.dart' as bip39;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

const _zeroMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _MockBuildSnapshot extends Mock
    implements BuildWalletManifestSnapshotUsecase {}

class _MockDeriveHandle extends Mock
    implements DeriveWalletManifestNostrHandleUsecase {}

class _MockDeriveRootKey extends Mock
    implements DeriveWalletManifestRootKeyUsecase {}

class _MockFetchRemoteManifest extends Mock
    implements FetchRemoteWalletManifestUsecase {}

class _MockRestoreSnapshot extends Mock
    implements RestoreWalletManifestSnapshotUsecase {}

class _MockRestoreRemoteManifest extends Mock
    implements RestoreRemoteWalletManifestUsecase {}

class _MockFileSaver extends Mock implements WalletManifestFileSaver {}

class _FakeNostrSnapshotStore implements WalletManifestNostrSnapshotStore {
  NostrKeychainHandle? publishedHandle;
  WalletManifestSnapshot? publishedSnapshot;
  NostrKeychainHandle? fetchedHandle;
  WalletManifestSnapshot? fetchedSnapshot;
  Object? publishError;
  Object? fetchError;

  @override
  Future<void> publish({
    required NostrKeychainHandle handle,
    required WalletManifestSnapshot snapshot,
  }) async {
    final error = publishError;
    if (error != null) throw error;
    publishedHandle = handle;
    publishedSnapshot = snapshot;
  }

  @override
  Future<WalletManifestSnapshot?> fetchLatest({
    required NostrKeychainHandle handle,
  }) async {
    final error = fetchError;
    if (error != null) throw error;
    fetchedHandle = handle;
    return fetchedSnapshot;
  }
}

void main() {
  group('PublishLocalWalletManifestUsecase', () {
    test(
      'builds and publishes with the dedicated wallet manifest key',
      () async {
        final snapshot = _snapshot();
        final buildSnapshot = _MockBuildSnapshot();
        final deriveHandle = _MockDeriveHandle();
        final store = _FakeNostrSnapshotStore();
        final usecase = PublishLocalWalletManifestUsecase(
          buildSnapshot: buildSnapshot,
          deriveHandle: deriveHandle,
          nostrSnapshotStore: store,
        );
        final xprv = _zeroMnemonicXprv();
        final handle = deriveWalletManifestHandleFromXprv(xprv);
        when(() => deriveHandle.execute()).thenAnswer(
          (_) async => WalletManifestNostrHandleContext(
            handle: handle,
            rootFingerprint: '73c5da0a',
          ),
        );
        when(
          () => buildSnapshot.execute(
            rootFingerprint: any(named: 'rootFingerprint'),
          ),
        ).thenAnswer((_) async => snapshot);

        final accountCount = await usecase.execute();

        verify(
          () => buildSnapshot.execute(rootFingerprint: '73c5da0a'),
        ).called(1);
        expect(accountCount, 1);
        expect(store.publishedSnapshot, snapshot);
        expect(store.publishedHandle!.publicKeyHex, handle.publicKeyHex);
        expect(
          store.publishedHandle!.publicKeyHex,
          isNot(deriveBullnymServerAuthHandleFromXprv(xprv).publicKeyHex),
        );
        expect(
          store.publishedHandle!.publicKeyHex,
          isNot(deriveNip05VerificationHandleFromXprv(xprv).publicKeyHex),
        );
      },
    );

    test('maps key derivation failures before building the snapshot', () async {
      final buildSnapshot = _MockBuildSnapshot();
      final deriveHandle = _MockDeriveHandle();
      final usecase = PublishLocalWalletManifestUsecase(
        buildSnapshot: buildSnapshot,
        deriveHandle: deriveHandle,
        nostrSnapshotStore: _FakeNostrSnapshotStore(),
      );
      when(() => deriveHandle.execute()).thenThrow(
        WalletManifestKeyDerivationException('wallet manifest key failed'),
      );

      await expectLater(
        usecase.execute(),
        throwsA(
          isA<WalletManifestSnapshotPublishException>().having(
            (e) => e.cause,
            'cause',
            isA<WalletManifestKeyDerivationException>(),
          ),
        ),
      );
      verifyNever(
        () => buildSnapshot.execute(
          rootFingerprint: any(named: 'rootFingerprint'),
        ),
      );
    });

    test('preserves typed store publish failures', () async {
      final snapshot = _snapshot();
      final buildSnapshot = _MockBuildSnapshot();
      final deriveHandle = _MockDeriveHandle();
      final error = WalletManifestSnapshotPublishException('relay failed');
      final store = _FakeNostrSnapshotStore()..publishError = error;
      final usecase = PublishLocalWalletManifestUsecase(
        buildSnapshot: buildSnapshot,
        deriveHandle: deriveHandle,
        nostrSnapshotStore: store,
      );
      when(() => deriveHandle.execute()).thenAnswer(
        (_) async => WalletManifestNostrHandleContext(
          handle: deriveWalletManifestHandleFromXprv(_zeroMnemonicXprv()),
          rootFingerprint: '73c5da0a',
        ),
      );
      when(
        () => buildSnapshot.execute(
          rootFingerprint: any(named: 'rootFingerprint'),
        ),
      ).thenAnswer((_) async => snapshot);

      await expectLater(usecase.execute(), throwsA(same(error)));
    });

    test(
      'carries remote accounts forward when publishing local snapshot',
      () async {
        final localSnapshot = _snapshot();
        final remoteAccount = _account(
          index: 77,
          network: WalletManifestNetwork.bitcoin,
          name: 'Deleted BTCPay-BTC',
        );
        final buildSnapshot = _MockBuildSnapshot();
        final deriveHandle = _MockDeriveHandle();
        final store = _FakeNostrSnapshotStore()
          ..fetchedSnapshot = WalletManifestSnapshot(
            createdAt: 100,
            accounts: [remoteAccount],
          );
        final usecase = PublishLocalWalletManifestUsecase(
          buildSnapshot: buildSnapshot,
          deriveHandle: deriveHandle,
          nostrSnapshotStore: store,
        );
        final handle = deriveWalletManifestHandleFromXprv(_zeroMnemonicXprv());
        when(() => deriveHandle.execute()).thenAnswer(
          (_) async => WalletManifestNostrHandleContext(
            handle: handle,
            rootFingerprint: '73c5da0a',
          ),
        );
        when(
          () => buildSnapshot.execute(
            rootFingerprint: any(named: 'rootFingerprint'),
          ),
        ).thenAnswer((_) async => localSnapshot);

        final accountCount = await usecase.execute();

        expect(accountCount, 2);
        expect(store.publishedSnapshot!.accounts, hasLength(2));
        expect(store.publishedSnapshot!.accounts, contains(remoteAccount));
        expect(
          store.publishedSnapshot!.accounts,
          contains(localSnapshot.accounts.single),
        );
      },
    );

    test('does not publish when remote preservation fetch fails', () async {
      final buildSnapshot = _MockBuildSnapshot();
      final deriveHandle = _MockDeriveHandle();
      final store = _FakeNostrSnapshotStore()..fetchError = Exception('relay');
      final usecase = PublishLocalWalletManifestUsecase(
        buildSnapshot: buildSnapshot,
        deriveHandle: deriveHandle,
        nostrSnapshotStore: store,
      );
      when(() => deriveHandle.execute()).thenAnswer(
        (_) async => WalletManifestNostrHandleContext(
          handle: deriveWalletManifestHandleFromXprv(_zeroMnemonicXprv()),
          rootFingerprint: '73c5da0a',
        ),
      );
      when(
        () => buildSnapshot.execute(
          rootFingerprint: any(named: 'rootFingerprint'),
        ),
      ).thenAnswer((_) async => _snapshot());

      await expectLater(
        usecase.execute(),
        throwsA(isA<WalletManifestSnapshotPublishException>()),
      );
      expect(store.publishedSnapshot, isNull);
    });
  });

  group('FetchRemoteWalletManifestUsecase', () {
    test('fetches with the dedicated wallet manifest key', () async {
      final snapshot = _snapshot();
      final deriveHandle = _MockDeriveHandle();
      final store = _FakeNostrSnapshotStore()..fetchedSnapshot = snapshot;
      final usecase = FetchRemoteWalletManifestUsecase(
        deriveHandle: deriveHandle,
        nostrSnapshotStore: store,
      );
      final xprv = _zeroMnemonicXprv();
      final handle = deriveWalletManifestHandleFromXprv(xprv);
      when(() => deriveHandle.execute()).thenAnswer(
        (_) async => WalletManifestNostrHandleContext(
          handle: handle,
          rootFingerprint: '73c5da0a',
        ),
      );

      final fetched = await usecase.execute();

      expect(fetched, snapshot);
      expect(store.fetchedHandle!.publicKeyHex, handle.publicKeyHex);
      expect(
        store.fetchedHandle!.publicKeyHex,
        isNot(deriveBullnymServerAuthHandleFromXprv(xprv).publicKeyHex),
      );
      expect(
        store.fetchedHandle!.publicKeyHex,
        isNot(deriveNip05VerificationHandleFromXprv(xprv).publicKeyHex),
      );
    });

    test('maps key derivation failures without retaining the xprv', () async {
      final deriveHandle = _MockDeriveHandle();
      final usecase = FetchRemoteWalletManifestUsecase(
        deriveHandle: deriveHandle,
        nostrSnapshotStore: _FakeNostrSnapshotStore(),
      );
      when(() => deriveHandle.execute()).thenThrow(
        WalletManifestKeyDerivationException('wallet manifest key failed'),
      );

      await expectLater(
        usecase.execute(),
        throwsA(
          isA<WalletManifestSnapshotFetchException>().having(
            (e) => e.cause,
            'cause',
            isA<WalletManifestKeyDerivationException>(),
          ),
        ),
      );
    });

    test('preserves typed store fetch failures', () async {
      final error = WalletManifestSnapshotFetchException('relay failed');
      final deriveHandle = _MockDeriveHandle();
      final store = _FakeNostrSnapshotStore()..fetchError = error;
      final usecase = FetchRemoteWalletManifestUsecase(
        deriveHandle: deriveHandle,
        nostrSnapshotStore: store,
      );
      when(() => deriveHandle.execute()).thenAnswer(
        (_) async => WalletManifestNostrHandleContext(
          handle: deriveWalletManifestHandleFromXprv(_zeroMnemonicXprv()),
          rootFingerprint: '73c5da0a',
        ),
      );

      await expectLater(usecase.execute(), throwsA(same(error)));
    });
  });

  group('CheckRemoteWalletManifestUsecase', () {
    test(
      'returns pretty encoded manifest payload from the fetched snapshot',
      () async {
        final fetchRemoteManifest = _MockFetchRemoteManifest();
        final usecase = CheckRemoteWalletManifestUsecase(
          fetchRemoteManifest: fetchRemoteManifest,
        );
        when(
          () => fetchRemoteManifest.execute(),
        ).thenAnswer((_) async => _snapshot());

        final result = await usecase.execute();

        expect(result, isNotNull);
        expect(result!.accountCount, 1);
        expect(result.manifestJson, contains('\n  "accounts": ['));
        expect(result.manifestJson, contains('"bip85_derivation_path"'));
      },
    );

    test('returns null when no remote snapshot exists', () async {
      final fetchRemoteManifest = _MockFetchRemoteManifest();
      final usecase = CheckRemoteWalletManifestUsecase(
        fetchRemoteManifest: fetchRemoteManifest,
      );
      when(() => fetchRemoteManifest.execute()).thenAnswer((_) async => null);

      final result = await usecase.execute();

      expect(result, isNull);
    });
  });

  group('RestoreRemoteWalletManifestUsecase', () {
    test('fetches and restores the latest remote manifest', () async {
      final snapshot = _snapshot();
      final fetchRemoteManifest = _MockFetchRemoteManifest();
      final restoreSnapshot = _MockRestoreSnapshot();
      final usecase = RestoreRemoteWalletManifestUsecase(
        fetchRemoteManifest: fetchRemoteManifest,
        restoreSnapshot: restoreSnapshot,
      );
      when(
        () => fetchRemoteManifest.execute(),
      ).thenAnswer((_) async => snapshot);
      when(() => restoreSnapshot.execute(snapshot: snapshot)).thenAnswer(
        (_) async => WalletManifestSnapshotRestoreResult(
          outcomes: [
            WalletManifestAccountRestoreOutcome(
              account: snapshot.accounts.first,
              status: WalletManifestRestoreStatus.created,
            ),
          ],
        ),
      );

      final result = await usecase.execute();

      expect(result, isNotNull);
      expect(result!.restoredCount, 1);
      expect(result.alreadyPresentCount, 0);
      expect(result.skippedCount, 0);
      expect(result.failedCount, 0);
      expect(result.walletStateMayHaveChanged, isTrue);
      expect(result.complete, isTrue);
      verify(() => fetchRemoteManifest.execute()).called(1);
      verify(() => restoreSnapshot.execute(snapshot: snapshot)).called(1);
    });

    test(
      'does not mark wallet state changed for already-present wallets',
      () async {
        final snapshot = _snapshot();
        final fetchRemoteManifest = _MockFetchRemoteManifest();
        final restoreSnapshot = _MockRestoreSnapshot();
        final usecase = RestoreRemoteWalletManifestUsecase(
          fetchRemoteManifest: fetchRemoteManifest,
          restoreSnapshot: restoreSnapshot,
        );
        when(
          () => fetchRemoteManifest.execute(),
        ).thenAnswer((_) async => snapshot);
        when(() => restoreSnapshot.execute(snapshot: snapshot)).thenAnswer(
          (_) async => WalletManifestSnapshotRestoreResult(
            outcomes: [
              WalletManifestAccountRestoreOutcome(
                account: snapshot.accounts.first,
                status: WalletManifestRestoreStatus.alreadyPresent,
                walletId: 'existing-wallet',
              ),
            ],
          ),
        );

        final result = await usecase.execute();

        expect(result, isNotNull);
        expect(result!.restoredCount, 0);
        expect(result.alreadyPresentCount, 1);
        expect(result.walletStateMayHaveChanged, isFalse);
      },
    );

    test(
      'marks wallet state changed when restore repairs an existing wallet origin',
      () async {
        final snapshot = _snapshot();
        final fetchRemoteManifest = _MockFetchRemoteManifest();
        final restoreSnapshot = _MockRestoreSnapshot();
        final usecase = RestoreRemoteWalletManifestUsecase(
          fetchRemoteManifest: fetchRemoteManifest,
          restoreSnapshot: restoreSnapshot,
        );
        when(
          () => fetchRemoteManifest.execute(),
        ).thenAnswer((_) async => snapshot);
        when(() => restoreSnapshot.execute(snapshot: snapshot)).thenAnswer(
          (_) async => WalletManifestSnapshotRestoreResult(
            outcomes: [
              WalletManifestAccountRestoreOutcome(
                account: snapshot.accounts.first,
                status: WalletManifestRestoreStatus.alreadyPresent,
                walletId: 'existing-wallet',
                walletStateChanged: true,
              ),
            ],
          ),
        );

        final result = await usecase.execute();

        expect(result, isNotNull);
        expect(result!.restoredCount, 0);
        expect(result.alreadyPresentCount, 1);
        expect(result.walletStateMayHaveChanged, isTrue);
      },
    );

    test(
      'marks wallet state changed when a failed restore has a wallet side effect',
      () async {
        final snapshot = _snapshot();
        final fetchRemoteManifest = _MockFetchRemoteManifest();
        final restoreSnapshot = _MockRestoreSnapshot();
        final usecase = RestoreRemoteWalletManifestUsecase(
          fetchRemoteManifest: fetchRemoteManifest,
          restoreSnapshot: restoreSnapshot,
        );
        when(
          () => fetchRemoteManifest.execute(),
        ).thenAnswer((_) async => snapshot);
        when(() => restoreSnapshot.execute(snapshot: snapshot)).thenAnswer(
          (_) async => WalletManifestSnapshotRestoreResult(
            outcomes: [
              WalletManifestAccountRestoreOutcome(
                account: snapshot.accounts.first,
                status: WalletManifestRestoreStatus.failed,
                walletId: 'partially-restored-wallet',
                failureStage: WalletManifestRestoreFailureStage.recordOrigin,
                cause: Exception('origin write failed'),
              ),
            ],
          ),
        );

        final result = await usecase.execute();

        expect(result, isNotNull);
        expect(result!.restoredCount, 0);
        expect(result.failedCount, 1);
        expect(result.walletStateMayHaveChanged, isTrue);
      },
    );

    test('returns null when no remote manifest exists', () async {
      final fetchRemoteManifest = _MockFetchRemoteManifest();
      final restoreSnapshot = _MockRestoreSnapshot();
      final usecase = RestoreRemoteWalletManifestUsecase(
        fetchRemoteManifest: fetchRemoteManifest,
        restoreSnapshot: restoreSnapshot,
      );
      when(() => fetchRemoteManifest.execute()).thenAnswer((_) async => null);

      final result = await usecase.execute();

      expect(result, isNull);
      verifyNever(() => restoreSnapshot.execute(snapshot: _snapshot()));
    });
  });

  group('SaveWalletManifestPayloadUsecase', () {
    test('saves the manifest JSON with the wallet manifest filename', () async {
      final fileSaver = _MockFileSaver();
      final usecase = SaveWalletManifestPayloadUsecase(fileSaver: fileSaver);
      when(
        () => fileSaver.save(
          content: '{"accounts":[]}',
          filename: SaveWalletManifestPayloadUsecase.filename,
        ),
      ).thenAnswer((_) async => true);

      final saved = await usecase.execute(manifestJson: '{"accounts":[]}');

      expect(saved, isTrue);
      verify(
        () => fileSaver.save(
          content: '{"accounts":[]}',
          filename: 'wallet-manifest.json',
        ),
      ).called(1);
    });
  });

  group('AuditRemoteWalletManifestUsecase', () {
    test(
      'compares remote manifest identities against manifest-recorded local identities',
      () async {
        final remoteSnapshot = WalletManifestSnapshot(
          createdAt: 1,
          accounts: [
            _account(index: 75, network: WalletManifestNetwork.liquid),
            _account(index: 76, network: WalletManifestNetwork.liquid),
          ],
        );
        final localSnapshot = WalletManifestSnapshot(
          createdAt: 2,
          accounts: [
            _account(index: 75, network: WalletManifestNetwork.liquid),
            _account(index: 77, network: WalletManifestNetwork.bitcoin),
          ],
        );
        final fetchRemoteManifest = _MockFetchRemoteManifest();
        final buildLocalSnapshot = _MockBuildSnapshot();
        final deriveRootKey = _MockDeriveRootKey();
        final usecase = AuditRemoteWalletManifestUsecase(
          fetchRemoteManifest: fetchRemoteManifest,
          buildLocalSnapshot: buildLocalSnapshot,
          deriveRootKey: deriveRootKey,
        );
        when(
          () => fetchRemoteManifest.execute(),
        ).thenAnswer((_) async => remoteSnapshot);
        when(() => deriveRootKey.execute()).thenAnswer(
          (_) async => const WalletManifestRootKeyContext(
            xprvBase58: 'xprv',
            rootFingerprint: '73c5da0a',
          ),
        );
        when(
          () => buildLocalSnapshot.execute(rootFingerprint: '73c5da0a'),
        ).thenAnswer((_) async => localSnapshot);

        final result = await usecase.execute();

        expect(result.matchingCount, 1);
        expect(result.missingLocalCount, 1);
        expect(result.missingRemoteCount, 1);
        expect(result.matches, isFalse);
        verify(
          () => buildLocalSnapshot.execute(rootFingerprint: '73c5da0a'),
        ).called(1);
      },
    );

    test('reports local identities when no remote manifest exists', () async {
      final fetchRemoteManifest = _MockFetchRemoteManifest();
      final buildLocalSnapshot = _MockBuildSnapshot();
      final deriveRootKey = _MockDeriveRootKey();
      final localSnapshot = WalletManifestSnapshot(
        createdAt: 2,
        accounts: [
          _account(index: 75, network: WalletManifestNetwork.liquid),
          _account(index: 77, network: WalletManifestNetwork.bitcoin),
        ],
      );
      final usecase = AuditRemoteWalletManifestUsecase(
        fetchRemoteManifest: fetchRemoteManifest,
        buildLocalSnapshot: buildLocalSnapshot,
        deriveRootKey: deriveRootKey,
      );
      when(() => deriveRootKey.execute()).thenAnswer(
        (_) async => const WalletManifestRootKeyContext(
          xprvBase58: 'xprv',
          rootFingerprint: '73c5da0a',
        ),
      );
      when(
        () => buildLocalSnapshot.execute(rootFingerprint: '73c5da0a'),
      ).thenAnswer((_) async => localSnapshot);
      when(() => fetchRemoteManifest.execute()).thenAnswer((_) async => null);

      final result = await usecase.execute();

      expect(result.remoteManifestFound, isFalse);
      expect(result.matchingCount, 0);
      expect(result.missingLocalCount, 0);
      expect(result.missingRemoteCount, 2);
      expect(result.matches, isFalse);
    });
  });

  group('StartWalletManifestRestoreAfterSeedRecoveryUsecase', () {
    test('starts remote manifest restore without awaiting it', () async {
      final restoreRemoteManifest = _MockRestoreRemoteManifest();
      final completer = Completer<RestoreRemoteWalletManifestResult?>();
      var restoredCallbackCount = 0;
      final usecase = StartWalletManifestRestoreAfterSeedRecoveryUsecase(
        restoreRemoteManifest: restoreRemoteManifest,
      );
      when(
        () => restoreRemoteManifest.execute(),
      ).thenAnswer((_) => completer.future);

      usecase.execute(
        onWalletStateMayHaveChanged: () => restoredCallbackCount++,
      );
      await Future<void>.delayed(Duration.zero);

      verify(() => restoreRemoteManifest.execute()).called(1);
      completer.complete(
        const RestoreRemoteWalletManifestResult(
          restoredCount: 1,
          alreadyPresentCount: 0,
          skippedCount: 0,
          failedCount: 0,
          walletStateMayHaveChanged: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(restoredCallbackCount, 1);
    });

    test('does not call changed callback when restore is unchanged', () async {
      final restoreRemoteManifest = _MockRestoreRemoteManifest();
      var restoredCallbackCount = 0;
      final usecase = StartWalletManifestRestoreAfterSeedRecoveryUsecase(
        restoreRemoteManifest: restoreRemoteManifest,
      );
      when(() => restoreRemoteManifest.execute()).thenAnswer(
        (_) async => const RestoreRemoteWalletManifestResult(
          restoredCount: 0,
          alreadyPresentCount: 1,
          skippedCount: 0,
          failedCount: 0,
          walletStateMayHaveChanged: false,
        ),
      );

      usecase.execute(
        onWalletStateMayHaveChanged: () => restoredCallbackCount++,
      );
      await Future<void>.delayed(Duration.zero);

      expect(restoredCallbackCount, 0);
    });

    test('swallows remote manifest restore failures', () async {
      final restoreRemoteManifest = _MockRestoreRemoteManifest();
      final usecase = StartWalletManifestRestoreAfterSeedRecoveryUsecase(
        restoreRemoteManifest: restoreRemoteManifest,
      );
      when(
        () => restoreRemoteManifest.execute(),
      ).thenThrow(Exception('relay offline'));

      usecase.execute();
      await Future<void>.delayed(Duration.zero);

      verify(() => restoreRemoteManifest.execute()).called(1);
    });
  });
}

WalletManifestAccount _account({
  required int index,
  required WalletManifestNetwork network,
  String? name,
}) {
  return WalletManifestAccount(
    rootFingerprint: '73c5da0a',
    bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: index),
    network: network,
    name: name,
    timestamp: 123,
  );
}

WalletManifestSnapshot _snapshot() {
  return WalletManifestSnapshot(
    createdAt: 123,
    accounts: [
      WalletManifestAccount(
        rootFingerprint: '73c5da0a',
        bip85DerivationPath: Bip85DerivationPath.mnemonic12(index: 76),
        network: WalletManifestNetwork.liquid,
        name: 'Payment Page-LBTC',
        timestamp: 123,
      ),
    ],
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
