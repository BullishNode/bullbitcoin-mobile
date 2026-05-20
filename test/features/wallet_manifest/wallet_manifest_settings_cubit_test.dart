import 'dart:async';

import 'package:bb_mobile/features/wallet_manifest/application/usecases/audit_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/check_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/get_wallet_manifest_public_key_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/publish_local_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/restore_remote_wallet_manifest_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/application/usecases/save_wallet_manifest_payload_usecase.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_cubit.dart';
import 'package:bb_mobile/features/wallet_manifest/presentation/wallet_manifest_settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockGetWalletManifestPublicKeyUsecase extends Mock
    implements GetWalletManifestPublicKeyUsecase {}

class _MockCheckRemoteWalletManifestUsecase extends Mock
    implements CheckRemoteWalletManifestUsecase {}

class _MockPublishLocalWalletManifestUsecase extends Mock
    implements PublishLocalWalletManifestUsecase {}

class _MockRestoreRemoteWalletManifestUsecase extends Mock
    implements RestoreRemoteWalletManifestUsecase {}

class _MockSaveWalletManifestPayloadUsecase extends Mock
    implements SaveWalletManifestPayloadUsecase {}

class _MockAuditRemoteWalletManifestUsecase extends Mock
    implements AuditRemoteWalletManifestUsecase {}

void main() {
  test('loads the wallet manifest public key', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    const npub = 'npub1manifest';
    when(() => getPublicKey.execute()).thenAnswer((_) async => npub);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.failed, isFalse);
    expect(cubit.state.npub, npub);
  });

  test('emits a generic error state without stale public key data', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => getPublicKey.execute()).thenThrow(Exception('raw failure'));
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.failed, isTrue);
    expect(cubit.state.npub, isNull);
  });

  test(
    'does not emit after close while public key loading is in flight',
    () async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final completer = Completer<String>();
      when(() => getPublicKey.execute()).thenAnswer((_) => completer.future);
      final cubit = _cubit(
        getPublicKey,
        checkRemoteManifest,
        publishLocalManifest,
      );

      final loadFuture = cubit.load();
      await cubit.close();
      completer.complete('npub1manifest');

      await loadFuture;
    },
  );

  test('checks the remote wallet manifest from Nostr', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();

    expect(cubit.state.checkingRemote, isFalse);
    expect(
      cubit.state.remoteCheckStatus,
      WalletManifestRemoteCheckStatus.loaded,
    );
    expect(cubit.state.remoteManifestJson, '{"accounts":[]}');
    expect(cubit.state.remoteManifestAccountCount, 0);
  });

  test('reports when no remote wallet manifest exists', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer((_) async => null);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();

    expect(cubit.state.checkingRemote, isFalse);
    expect(
      cubit.state.remoteCheckStatus,
      WalletManifestRemoteCheckStatus.missing,
    );
    expect(cubit.state.remoteManifestJson, isNull);
  });

  test('emits a generic remote check failure without raw errors', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(
      () => checkRemoteManifest.execute(),
    ).thenThrow(Exception('relay details'));
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();

    expect(cubit.state.checkingRemote, isFalse);
    expect(
      cubit.state.remoteCheckStatus,
      WalletManifestRemoteCheckStatus.failed,
    );
    expect(cubit.state.remoteManifestJson, isNull);
  });

  test('publishes the local wallet manifest to Nostr', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 2);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.publishLocalManifest();

    expect(cubit.state.publishing, isFalse);
    expect(cubit.state.publishStatus, WalletManifestPublishStatus.succeeded);
    expect(cubit.state.publishedManifestAccountCount, 2);
    verify(() => publishLocalManifest.execute()).called(1);
  });

  test('does not start duplicate local manifest publishes', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final completer = Completer<int>();
    when(
      () => publishLocalManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    final firstPublish = cubit.publishLocalManifest();
    await cubit.publishLocalManifest();

    completer.complete(1);
    await firstPublish;

    verify(() => publishLocalManifest.execute()).called(1);
    expect(cubit.state.publishStatus, WalletManifestPublishStatus.succeeded);
  });

  test('emits a generic local manifest publish failure', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(
      () => publishLocalManifest.execute(),
    ).thenThrow(Exception('relay details'));
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.publishLocalManifest();

    expect(cubit.state.publishing, isFalse);
    expect(cubit.state.publishStatus, WalletManifestPublishStatus.failed);
    expect(cubit.state.publishedManifestAccountCount, isNull);
  });

  test('does not publish while a remote check is in flight', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final completer = Completer<CheckRemoteWalletManifestResult?>();
    when(
      () => checkRemoteManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    final check = cubit.checkRemoteManifest();
    await cubit.publishLocalManifest();

    completer.complete(null);
    await check;

    verify(() => checkRemoteManifest.execute()).called(1);
    verifyNever(() => publishLocalManifest.execute());
  });

  test('does not check the remote manifest while publishing', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final completer = Completer<int>();
    when(
      () => publishLocalManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    final publish = cubit.publishLocalManifest();
    await cubit.checkRemoteManifest();

    completer.complete(1);
    await publish;

    verify(() => publishLocalManifest.execute()).called(1);
    verifyNever(() => checkRemoteManifest.execute());
  });

  test('publishing clears previously fetched remote manifest data', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"old":true}',
        accountCount: 1,
      ),
    );
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 2);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    await cubit.publishLocalManifest();

    expect(cubit.state.remoteCheckStatus, WalletManifestRemoteCheckStatus.idle);
    expect(cubit.state.remoteManifestJson, isNull);
    expect(cubit.state.remoteManifestAccountCount, isNull);
  });

  test('checking clears stale publish and recovery results', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 1);
    when(() => restoreRemoteManifest.execute()).thenAnswer(
      (_) async => const RestoreRemoteWalletManifestResult(
        restoredCount: 1,
        alreadyPresentCount: 0,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"latest":true}',
        accountCount: 1,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.publishLocalManifest();
    await cubit.restoreRemoteManifest();
    await cubit.checkRemoteManifest();

    expect(cubit.state.publishStatus, WalletManifestPublishStatus.idle);
    expect(cubit.state.publishedManifestAccountCount, isNull);
    expect(
      cubit.state.manualRestoreStatus,
      WalletManifestManualRestoreStatus.idle,
    );
    expect(cubit.state.manualRestoreRestoredCount, isNull);
    expect(
      cubit.state.remoteCheckStatus,
      WalletManifestRemoteCheckStatus.loaded,
    );
  });

  test('publishing clears stale recovery results', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => restoreRemoteManifest.execute()).thenAnswer(
      (_) async => const RestoreRemoteWalletManifestResult(
        restoredCount: 1,
        alreadyPresentCount: 0,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 1);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.restoreRemoteManifest();
    await cubit.publishLocalManifest();

    expect(
      cubit.state.manualRestoreStatus,
      WalletManifestManualRestoreStatus.idle,
    );
    expect(cubit.state.manualRestoreRestoredCount, isNull);
    expect(cubit.state.publishStatus, WalletManifestPublishStatus.succeeded);
  });

  test('saves the fetched remote wallet manifest payload', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenAnswer((_) async => true);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    await cubit.saveRemoteManifest();

    expect(cubit.state.saveStatus, WalletManifestSaveStatus.succeeded);
    verify(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).called(1);
  });

  test('reports cancelled and failed wallet manifest saves', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenAnswer((_) async => false);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    await cubit.saveRemoteManifest();

    expect(cubit.state.saveStatus, WalletManifestSaveStatus.cancelled);

    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenThrow(Exception('disk details'));
    await cubit.saveRemoteManifest();

    expect(cubit.state.saveStatus, WalletManifestSaveStatus.failed);
  });

  test('does not save before a remote manifest is fetched', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);

    await cubit.saveRemoteManifest();

    verifyNever(
      () => saveWalletManifestPayload.execute(
        manifestJson: any(named: 'manifestJson'),
      ),
    );
    expect(cubit.state.saveStatus, WalletManifestSaveStatus.idle);
  });

  test('does not start duplicate wallet manifest saves', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final completer = Completer<bool>();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    final firstSave = cubit.saveRemoteManifest();
    await cubit.saveRemoteManifest();

    completer.complete(true);
    await firstSave;

    verify(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).called(1);
    expect(cubit.state.saveStatus, WalletManifestSaveStatus.succeeded);
  });

  test('does not check publish or restore while save is in flight', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final completer = Completer<bool>();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"accounts":[]}',
        accountCount: 0,
      ),
    );
    when(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    final save = cubit.saveRemoteManifest();
    await cubit.checkRemoteManifest();
    await cubit.publishLocalManifest();
    await cubit.restoreRemoteManifest();

    completer.complete(true);
    await save;

    verify(() => checkRemoteManifest.execute()).called(1);
    verify(
      () => saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
    ).called(1);
    verifyNever(() => publishLocalManifest.execute());
    verifyNever(() => restoreRemoteManifest.execute());
  });

  test('audits the remote wallet manifest against local identities', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
    when(() => auditRemoteWalletManifest.execute()).thenAnswer(
      (_) async => const AuditRemoteWalletManifestResult(
        matchingCount: 2,
        missingLocalCount: 0,
        missingRemoteCount: 0,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
      auditRemoteWalletManifest,
    );
    addTearDown(cubit.close);

    await cubit.auditRemoteManifest();

    expect(cubit.state.auditStatus, WalletManifestAuditStatus.matches);
    expect(cubit.state.auditMatchingCount, 2);
    expect(cubit.state.auditMissingLocalCount, 0);
    expect(cubit.state.auditMissingRemoteCount, 0);
    verify(() => auditRemoteWalletManifest.execute()).called(1);
  });

  test('reports differing remote wallet manifest audit results', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
    final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
    when(() => auditRemoteWalletManifest.execute()).thenAnswer(
      (_) async => const AuditRemoteWalletManifestResult(
        matchingCount: 1,
        missingLocalCount: 2,
        missingRemoteCount: 3,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
      saveWalletManifestPayload,
      auditRemoteWalletManifest,
    );
    addTearDown(cubit.close);

    await cubit.auditRemoteManifest();

    expect(cubit.state.auditStatus, WalletManifestAuditStatus.differs);
    expect(cubit.state.auditMatchingCount, 1);
    expect(cubit.state.auditMissingLocalCount, 2);
    expect(cubit.state.auditMissingRemoteCount, 3);
  });

  test(
    'reports missing and failed remote wallet manifest audit states',
    () async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
      final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
      final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
      when(() => auditRemoteWalletManifest.execute()).thenAnswer(
        (_) async => const AuditRemoteWalletManifestResult(
          remoteManifestFound: false,
          matchingCount: 0,
          missingLocalCount: 0,
          missingRemoteCount: 2,
        ),
      );
      final cubit = _cubit(
        getPublicKey,
        checkRemoteManifest,
        publishLocalManifest,
        restoreRemoteManifest,
        saveWalletManifestPayload,
        auditRemoteWalletManifest,
      );
      addTearDown(cubit.close);

      await cubit.auditRemoteManifest();

      expect(cubit.state.auditStatus, WalletManifestAuditStatus.missing);
      expect(cubit.state.auditMissingRemoteCount, 2);

      when(
        () => auditRemoteWalletManifest.execute(),
      ).thenThrow(Exception('audit details'));
      await cubit.auditRemoteManifest();

      expect(cubit.state.auditStatus, WalletManifestAuditStatus.failed);
    },
  );

  test(
    'does not check publish restore or save while audit is in flight',
    () async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
      final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
      final auditRemoteWalletManifest = _MockAuditRemoteWalletManifestUsecase();
      final completer = Completer<AuditRemoteWalletManifestResult>();
      when(
        () => auditRemoteWalletManifest.execute(),
      ).thenAnswer((_) => completer.future);
      final cubit = _cubit(
        getPublicKey,
        checkRemoteManifest,
        publishLocalManifest,
        restoreRemoteManifest,
        saveWalletManifestPayload,
        auditRemoteWalletManifest,
      );
      addTearDown(cubit.close);

      final audit = cubit.auditRemoteManifest();
      await cubit.checkRemoteManifest();
      await cubit.publishLocalManifest();
      await cubit.restoreRemoteManifest();
      await cubit.saveRemoteManifest();

      completer.complete(
        const AuditRemoteWalletManifestResult(
          matchingCount: 0,
          missingLocalCount: 0,
          missingRemoteCount: 0,
        ),
      );
      await audit;

      verify(() => auditRemoteWalletManifest.execute()).called(1);
      verifyNever(() => checkRemoteManifest.execute());
      verifyNever(() => publishLocalManifest.execute());
      verifyNever(() => restoreRemoteManifest.execute());
      verifyNever(
        () => saveWalletManifestPayload.execute(
          manifestJson: any(named: 'manifestJson'),
        ),
      );
    },
  );

  test(
    'does not audit while another wallet manifest operation is in flight',
    () async {
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final auditDuringCheck = _MockAuditRemoteWalletManifestUsecase();
      final checkCompleter = Completer<CheckRemoteWalletManifestResult?>();
      when(
        () => checkRemoteManifest.execute(),
      ).thenAnswer((_) => checkCompleter.future);
      var cubit = _cubit(
        _MockGetWalletManifestPublicKeyUsecase(),
        checkRemoteManifest,
        _MockPublishLocalWalletManifestUsecase(),
        _MockRestoreRemoteWalletManifestUsecase(),
        _MockSaveWalletManifestPayloadUsecase(),
        auditDuringCheck,
      );
      addTearDown(cubit.close);
      final check = cubit.checkRemoteManifest();
      await cubit.auditRemoteManifest();
      checkCompleter.complete(null);
      await check;
      verifyNever(() => auditDuringCheck.execute());

      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final auditDuringPublish = _MockAuditRemoteWalletManifestUsecase();
      final publishCompleter = Completer<int>();
      when(
        () => publishLocalManifest.execute(),
      ).thenAnswer((_) => publishCompleter.future);
      cubit = _cubit(
        _MockGetWalletManifestPublicKeyUsecase(),
        _MockCheckRemoteWalletManifestUsecase(),
        publishLocalManifest,
        _MockRestoreRemoteWalletManifestUsecase(),
        _MockSaveWalletManifestPayloadUsecase(),
        auditDuringPublish,
      );
      addTearDown(cubit.close);
      final publish = cubit.publishLocalManifest();
      await cubit.auditRemoteManifest();
      publishCompleter.complete(1);
      await publish;
      verifyNever(() => auditDuringPublish.execute());

      final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
      final auditDuringRestore = _MockAuditRemoteWalletManifestUsecase();
      final restoreCompleter = Completer<RestoreRemoteWalletManifestResult?>();
      when(
        () => restoreRemoteManifest.execute(),
      ).thenAnswer((_) => restoreCompleter.future);
      cubit = _cubit(
        _MockGetWalletManifestPublicKeyUsecase(),
        _MockCheckRemoteWalletManifestUsecase(),
        _MockPublishLocalWalletManifestUsecase(),
        restoreRemoteManifest,
        _MockSaveWalletManifestPayloadUsecase(),
        auditDuringRestore,
      );
      addTearDown(cubit.close);
      final restore = cubit.restoreRemoteManifest();
      await cubit.auditRemoteManifest();
      restoreCompleter.complete(null);
      await restore;
      verifyNever(() => auditDuringRestore.execute());

      final saveCheckRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final saveWalletManifestPayload = _MockSaveWalletManifestPayloadUsecase();
      final auditDuringSave = _MockAuditRemoteWalletManifestUsecase();
      final saveCompleter = Completer<bool>();
      when(() => saveCheckRemoteManifest.execute()).thenAnswer(
        (_) async => const CheckRemoteWalletManifestResult(
          manifestJson: '{"accounts":[]}',
          accountCount: 0,
        ),
      );
      when(
        () =>
            saveWalletManifestPayload.execute(manifestJson: '{"accounts":[]}'),
      ).thenAnswer((_) => saveCompleter.future);
      cubit = _cubit(
        _MockGetWalletManifestPublicKeyUsecase(),
        saveCheckRemoteManifest,
        _MockPublishLocalWalletManifestUsecase(),
        _MockRestoreRemoteWalletManifestUsecase(),
        saveWalletManifestPayload,
        auditDuringSave,
      );
      addTearDown(cubit.close);
      await cubit.checkRemoteManifest();
      final save = cubit.saveRemoteManifest();
      await cubit.auditRemoteManifest();
      saveCompleter.complete(true);
      await save;
      verifyNever(() => auditDuringSave.execute());
    },
  );

  test('recovers wallets from the remote wallet manifest', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => restoreRemoteManifest.execute()).thenAnswer(
      (_) async => const RestoreRemoteWalletManifestResult(
        restoredCount: 2,
        alreadyPresentCount: 1,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.restoreRemoteManifest();

    expect(cubit.state.restoring, isFalse);
    expect(
      cubit.state.manualRestoreStatus,
      WalletManifestManualRestoreStatus.completed,
    );
    expect(cubit.state.manualRestoreRestoredCount, 2);
    expect(cubit.state.manualRestoreAlreadyPresentCount, 1);
    expect(cubit.state.manualRestoreSkippedCount, 0);
    expect(cubit.state.manualRestoreFailedCount, 0);
    verify(() => restoreRemoteManifest.execute()).called(1);
  });

  test('reports partial remote manifest recovery results', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => restoreRemoteManifest.execute()).thenAnswer(
      (_) async => const RestoreRemoteWalletManifestResult(
        restoredCount: 1,
        alreadyPresentCount: 1,
        skippedCount: 1,
        failedCount: 1,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.restoreRemoteManifest();

    expect(
      cubit.state.manualRestoreStatus,
      WalletManifestManualRestoreStatus.needsAttention,
    );
    expect(cubit.state.manualRestoreSkippedCount, 1);
    expect(cubit.state.manualRestoreFailedCount, 1);
  });

  test(
    'reports when no readable remote wallet manifest can be recovered',
    () async {
      final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
      final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
      final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
      final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
      when(() => restoreRemoteManifest.execute()).thenAnswer((_) async => null);
      final cubit = _cubit(
        getPublicKey,
        checkRemoteManifest,
        publishLocalManifest,
        restoreRemoteManifest,
      );
      addTearDown(cubit.close);

      await cubit.restoreRemoteManifest();

      expect(
        cubit.state.manualRestoreStatus,
        WalletManifestManualRestoreStatus.missing,
      );
    },
  );

  test('emits a generic remote manifest recovery failure', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(
      () => restoreRemoteManifest.execute(),
    ).thenThrow(Exception('restore details'));
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.restoreRemoteManifest();

    expect(
      cubit.state.manualRestoreStatus,
      WalletManifestManualRestoreStatus.failed,
    );
  });

  test('restore clears stale check and publish results', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    when(() => checkRemoteManifest.execute()).thenAnswer(
      (_) async => const CheckRemoteWalletManifestResult(
        manifestJson: '{"old":true}',
        accountCount: 1,
      ),
    );
    when(() => publishLocalManifest.execute()).thenAnswer((_) async => 1);
    when(() => restoreRemoteManifest.execute()).thenAnswer(
      (_) async => const RestoreRemoteWalletManifestResult(
        restoredCount: 1,
        alreadyPresentCount: 0,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    await cubit.checkRemoteManifest();
    await cubit.publishLocalManifest();
    await cubit.checkRemoteManifest();
    await cubit.restoreRemoteManifest();

    expect(cubit.state.remoteCheckStatus, WalletManifestRemoteCheckStatus.idle);
    expect(cubit.state.remoteManifestJson, isNull);
    expect(cubit.state.remoteManifestAccountCount, isNull);
    expect(cubit.state.publishStatus, WalletManifestPublishStatus.idle);
    expect(cubit.state.publishedManifestAccountCount, isNull);
  });

  test('does not restore while a remote check is in flight', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final completer = Completer<CheckRemoteWalletManifestResult?>();
    when(
      () => checkRemoteManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    final check = cubit.checkRemoteManifest();
    await cubit.restoreRemoteManifest();

    completer.complete(null);
    await check;

    verify(() => checkRemoteManifest.execute()).called(1);
    verifyNever(() => restoreRemoteManifest.execute());
  });

  test('does not restore while publishing is in flight', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final completer = Completer<int>();
    when(
      () => publishLocalManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    final publish = cubit.publishLocalManifest();
    await cubit.restoreRemoteManifest();

    completer.complete(1);
    await publish;

    verify(() => publishLocalManifest.execute()).called(1);
    verifyNever(() => restoreRemoteManifest.execute());
  });

  test('does not check or publish while restore is in flight', () async {
    final getPublicKey = _MockGetWalletManifestPublicKeyUsecase();
    final checkRemoteManifest = _MockCheckRemoteWalletManifestUsecase();
    final publishLocalManifest = _MockPublishLocalWalletManifestUsecase();
    final restoreRemoteManifest = _MockRestoreRemoteWalletManifestUsecase();
    final completer = Completer<RestoreRemoteWalletManifestResult?>();
    when(
      () => restoreRemoteManifest.execute(),
    ).thenAnswer((_) => completer.future);
    final cubit = _cubit(
      getPublicKey,
      checkRemoteManifest,
      publishLocalManifest,
      restoreRemoteManifest,
    );
    addTearDown(cubit.close);

    final restore = cubit.restoreRemoteManifest();
    await cubit.checkRemoteManifest();
    await cubit.publishLocalManifest();

    completer.complete(
      const RestoreRemoteWalletManifestResult(
        restoredCount: 0,
        alreadyPresentCount: 0,
        skippedCount: 0,
        failedCount: 0,
      ),
    );
    await restore;

    verify(() => restoreRemoteManifest.execute()).called(1);
    verifyNever(() => checkRemoteManifest.execute());
    verifyNever(() => publishLocalManifest.execute());
  });
}

WalletManifestSettingsCubit _cubit(
  GetWalletManifestPublicKeyUsecase getPublicKey,
  CheckRemoteWalletManifestUsecase checkRemoteManifest,
  PublishLocalWalletManifestUsecase publishLocalManifest, [
  RestoreRemoteWalletManifestUsecase? restoreRemoteManifest,
  SaveWalletManifestPayloadUsecase? saveWalletManifestPayload,
  AuditRemoteWalletManifestUsecase? auditRemoteWalletManifest,
]) {
  return WalletManifestSettingsCubit(
    getPublicKey: getPublicKey,
    checkRemoteManifest: checkRemoteManifest,
    publishLocalManifest: publishLocalManifest,
    restoreRemoteManifest:
        restoreRemoteManifest ?? _MockRestoreRemoteWalletManifestUsecase(),
    saveWalletManifestPayload:
        saveWalletManifestPayload ?? _MockSaveWalletManifestPayloadUsecase(),
    auditRemoteWalletManifest:
        auditRemoteWalletManifest ?? _MockAuditRemoteWalletManifestUsecase(),
  );
}
