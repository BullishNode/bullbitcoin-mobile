import 'package:bb_mobile/core/failures/failure.dart';
import 'package:bb_mobile/core/storage/sqlite_database.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_backup_blob.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/get_paid_fixtures.dart';
import 'support/override_wallet_metadata_backup_remote.dart';

const _fakeLabelCount = 1000;

T _unwrap<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure('Expected success, got $failure'),
};

WalletMetadataBackupFailure _unwrapFailure<T>(
  Result<T, WalletMetadataBackupFailure> result,
) => switch (result) {
  Ok() => throw TestFailure('Expected failure, got success'),
  Err(:final failure) => failure,
};

Bip329LabelRecord _label(int index) => Bip329LabelRecord(
  type: 'tx',
  reference: index.toRadixString(16).padLeft(64, '0'),
  label: 'metadata-backup-$index',
  origin: 'wallet-backup-e2e',
);

List<Bip329LabelRecord> _labels(int count) =>
    List.generate(count, (index) => _label(index));

Set<String> _portableLabels(List<Bip329LabelRecord> labels) => labels
    .map(
      (label) =>
          '${label.type}\u0000${label.reference}\u0000${label.label}\u0000'
          '${label.origin ?? ''}',
    )
    .toSet();

Future<void> _clearLocalMetadataStore() async {
  final database = locator<SqliteDatabase>();
  await database.transaction(() async {
    await database.delete(database.labels).go();
    await database.delete(database.walletMetadataBackupStates).go();
  });
}

typedef _MetadataHarness = ({
  WalletMetadataBackupFacade metadata,
  LabelsFacade labels,
  FakeBullnymClient fake,
  Set<String> walletIds,
});

Future<_MetadataHarness> _bootstrapMetadataHarness() async {
  await _clearLocalMetadataStore();
  await ensureFixtureSeed();

  final fake = FakeBullnymClient();
  await overrideWalletMetadataBackupRemote(locator, fake);

  final wallets = await locator<CreateDefaultWalletsUsecase>().execute(
    mnemonicWords: getPaidFixtureMnemonicWords,
  );

  return (
    metadata: locator<WalletMetadataBackupFacade>(),
    labels: locator<LabelsFacade>(),
    fake: fake,
    walletIds: wallets.map((wallet) => wallet.id).toSet(),
  );
}

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('enabled wallet metadata backup publishes exactly one blob', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final expected = _labels(1);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(expected),
    );
    expect(restored.restoredCount, expected.length);

    final published = _unwrap(await harness.metadata.backupNow());
    expect(published.status, WalletMetadataPublishStatus.stored);
    expect(published.remoteGeneration, greaterThan(0));
    expect(harness.fake.backupStoreCalls, hasLength(1));
    expect(
      harness.fake.backupStoreCalls.single.stream,
      BullnymBackupStream.walletMetadata,
    );
    expect(_unwrap(await harness.metadata.getState()).dirty, isFalse);
  });

  test('unchanged backup does not create a second backup store', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final expected = _labels(1);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(expected),
    );
    expect(restored.restoredCount, expected.length);

    final first = _unwrap(await harness.metadata.backupNow());
    expect(first.status, WalletMetadataPublishStatus.stored);
    expect(harness.fake.backupStoreCalls, hasLength(1));

    final second = _unwrap(await harness.metadata.backupNow());
    expect(second.status, WalletMetadataPublishStatus.notReady);
    expect(harness.fake.backupStoreCalls, hasLength(1));
  });

  test('disabling backup before delete removes the remote copy', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final expected = _labels(1);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(expected),
    );
    expect(restored.restoredCount, expected.length);

    final published = _unwrap(await harness.metadata.backupNow());
    expect(published.status, WalletMetadataPublishStatus.stored);
    expect(harness.fake.backupStoreCalls, hasLength(1));

    _unwrap(await harness.metadata.setEnabled(false));

    final deleted = await harness.metadata.deleteRemoteBackup();
    expect(deleted, isA<Ok<void, WalletMetadataBackupFailure>>());
    expect(_unwrap(await harness.metadata.getState()).enabled, isFalse);
    expect(harness.fake.backupDeleteCalls, hasLength(1));
    expect(
      harness.fake.backupDeleteCalls.single.stream,
      BullnymBackupStream.walletMetadata,
    );
  });

  test(
    'wallet metadata CAS conflict keeps state dirty and avoids extra writes',
    () async {
      final harness = await _bootstrapMetadataHarness();
      _unwrap(await harness.metadata.setEnabled(true));

      final expected = _labels(2);
      final restored = _unwrap(
        await harness.labels.restoreBip329LabelRecords(expected),
      );
      expect(restored.restoredCount, expected.length);

      harness.fake.walletMetadataStoreConflictCount = 2;
      final first = await harness.metadata.backupNow();
      final conflictFailure = _unwrapFailure(first);
      expect(conflictFailure, isA<WalletMetadataBackupConflictFailure>());
      expect(harness.fake.backupStoreCalls, hasLength(2));
      expect(_unwrap(await harness.metadata.getState()).dirty, isTrue);

      harness.fake.walletMetadataStoreConflictCount = 0;
      final retried = _unwrap(await harness.metadata.backupNow());
      expect(retried.status, WalletMetadataPublishStatus.stored);
      expect(_unwrap(await harness.metadata.getState()).dirty, isFalse);

      final unchanged = _unwrap(await harness.metadata.backupNow());
      expect(unchanged.status, WalletMetadataPublishStatus.notReady);
      expect(harness.fake.backupStoreCalls, hasLength(3));
    },
  );

  test('recovery restores labels after local metadata deletion', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final expected = _labels(4);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(expected),
    );
    expect(restored.restoredCount, expected.length);

    final published = _unwrap(await harness.metadata.backupNow());
    expect(published.status, WalletMetadataPublishStatus.stored);

    final recovery = await harness.metadata.beginRecoverySession();
    try {
      await _clearLocalMetadataStore();
      expect(await harness.labels.fetchAll(), isEmpty);

      final recovered = _unwrap(
        await recovery.recover(createdWalletRefs: harness.walletIds),
      );
      expect(recovered.status, WalletMetadataRecoveryStatus.recovered);
    } finally {
      recovery.close();
    }

    final recoveredLabels = _unwrap(
      await harness.labels.exportBip329LabelRecords(),
    );
    expect(recoveredLabels, hasLength(expected.length));
    expect(_portableLabels(recoveredLabels), _portableLabels(expected));
  });

  test(
    'recovery treats deleted remote metadata backup as absent tombstone',
    () async {
      final harness = await _bootstrapMetadataHarness();
      _unwrap(await harness.metadata.setEnabled(true));

      final deletedLabels = _labels(2);
      final restored = _unwrap(
        await harness.labels.restoreBip329LabelRecords(deletedLabels),
      );
      expect(restored.restoredCount, deletedLabels.length);

      final published = _unwrap(await harness.metadata.backupNow());
      expect(published.status, WalletMetadataPublishStatus.stored);
      expect(published.remoteGeneration, isNotNull);
      expect(harness.fake.backupStoreCalls, hasLength(1));

      _unwrap(await harness.metadata.setEnabled(false));
      final deleted = await harness.metadata.deleteRemoteBackup();
      expect(deleted, isA<Ok<void, WalletMetadataBackupFailure>>());
      expect(harness.fake.backupDeleteCalls, hasLength(1));
      final tombstoneGeneration = published.remoteGeneration! + 1;
      expect(
        harness.fake.backupDeleteCalls.single.generation,
        tombstoneGeneration,
      );

      await _clearLocalMetadataStore();
      expect(await harness.labels.fetchAll(), isEmpty);
      final storeCallsBeforeRecovery = harness.fake.backupStoreCalls.length;

      final recovery = await harness.metadata.beginRecoverySession();
      try {
        final recovered = _unwrap(
          await recovery.recover(createdWalletRefs: harness.walletIds),
        );
        expect(recovered.status, WalletMetadataRecoveryStatus.noSnapshotFound);
        expect(recovered.applyResult, isNull);
      } finally {
        recovery.close();
      }

      expect(await harness.labels.fetchAll(), isEmpty);
      expect(
        harness.fake.backupStoreCalls,
        hasLength(storeCallsBeforeRecovery),
      );
      expect(harness.fake.backupFetchResults.last.found, isFalse);
      expect(
        harness.fake.backupFetchResults.last.generation,
        tombstoneGeneration,
      );

      final secondRecovery = await harness.metadata.beginRecoverySession();
      try {
        final refetched = _unwrap(
          await secondRecovery.recover(createdWalletRefs: harness.walletIds),
        );
        expect(refetched.status, WalletMetadataRecoveryStatus.noSnapshotFound);
        expect(refetched.applyResult, isNull);
      } finally {
        secondRecovery.close();
      }

      expect(await harness.labels.fetchAll(), isEmpty);
      expect(
        harness.fake.backupStoreCalls,
        hasLength(storeCallsBeforeRecovery),
      );
      expect(harness.fake.backupFetchResults.last.found, isFalse);
      expect(
        harness.fake.backupFetchResults.last.generation,
        tombstoneGeneration,
      );
    },
  );

  test('publishing 1000 labels stays in a single backup store call', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final expected = _labels(_fakeLabelCount);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(expected),
    );
    expect(restored.restoredCount, expected.length);

    final published = _unwrap(await harness.metadata.backupNow());
    expect(published.status, WalletMetadataPublishStatus.stored);
    expect(harness.fake.backupStoreCalls, hasLength(1));
    expect(
      harness.fake.backupStoreCalls.single.stream,
      BullnymBackupStream.walletMetadata,
    );
    expect(published.remoteGeneration, 1);
  });

  test('labels added after publish are included in next backup', () async {
    final harness = await _bootstrapMetadataHarness();
    _unwrap(await harness.metadata.setEnabled(true));

    final initial = _labels(3);
    final restored = _unwrap(
      await harness.labels.restoreBip329LabelRecords(initial),
    );
    expect(restored.restoredCount, initial.length);

    final first = _unwrap(await harness.metadata.backupNow());
    expect(first.status, WalletMetadataPublishStatus.stored);
    expect(harness.fake.backupStoreCalls, hasLength(1));

    final added = <Bip329LabelRecord>[_label(100)];
    final secondRestore = _unwrap(
      await harness.labels.restoreBip329LabelRecords(added),
    );
    expect(secondRestore.restoredCount, added.length);

    final second = _unwrap(await harness.metadata.backupNow());
    expect(second.status, WalletMetadataPublishStatus.stored);
    expect(harness.fake.backupStoreCalls, hasLength(2));

    await _clearLocalMetadataStore();
    final expected = [...initial, ...added];

    final recovery = await harness.metadata.beginRecoverySession();
    try {
      final recoverResult = _unwrap(
        await recovery.recover(createdWalletRefs: harness.walletIds),
      );
      expect(recoverResult.status, WalletMetadataRecoveryStatus.recovered);
    } finally {
      recovery.close();
    }

    final recovered = _unwrap(await harness.labels.exportBip329LabelRecords());
    expect(_portableLabels(recovered), _portableLabels(expected));
  });
}
