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

const _liveBullnym = bool.fromEnvironment('BULLNYM_BACKUP_LIVE');
const _fakeLabelCount = 1000;

T _unwrap<T, F extends Failure>(Result<T, F> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final failure) => throw TestFailure('Expected success, got $failure'),
};

List<Bip329LabelRecord> _labels(int count) => List.generate(count, (index) {
  return Bip329LabelRecord(
    type: 'tx',
    reference: index.toRadixString(16).padLeft(64, '0'),
    label: 'metadata-backup-$index',
    origin: 'wallet-backup-e2e',
  );
});

Set<String> _portableLabels(List<Bip329LabelRecord> labels) => labels
    .map(
      (label) =>
          '${label.type}\u0000${label.reference}\u0000${label.label}\u0000'
          '${label.origin ?? ''}',
    )
    .toSet();

Future<void> main({bool isInitialized = false}) async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!isInitialized) await Bull.init();

  test('Bullnym wallet metadata backup restores BIP329 labels', () async {
    final FakeBullnymClient? fake;
    if (_liveBullnym) {
      fake = null;
    } else {
      fake = FakeBullnymClient();
      await overrideWalletMetadataBackupRemote(locator, fake);
    }

    final wallets = await locator<CreateDefaultWalletsUsecase>().execute(
      mnemonicWords: _liveBullnym ? null : getPaidFixtureMnemonicWords,
    );
    final walletIds = wallets.map((wallet) => wallet.id).toSet();
    expect(walletIds, isNotEmpty);

    final metadata = locator<WalletMetadataBackupFacade>();
    final labels = locator<LabelsFacade>();
    _unwrap(await metadata.setEnabled(true));

    final expected = _labels(_liveBullnym ? 1 : _fakeLabelCount);
    final restoredLocally = _unwrap(
      await labels.restoreBip329LabelRecords(expected),
    );
    expect(restoredLocally.restoredCount, expected.length);

    final published = _unwrap(await metadata.backupNow());
    expect(published.status, WalletMetadataPublishStatus.stored);
    expect(published.remoteGeneration, greaterThan(0));
    if (fake != null) {
      expect(fake.backupStoreCalls, hasLength(1));
      expect(
        fake.backupStoreCalls.single.stream,
        BullnymBackupStream.walletMetadata,
      );
    }

    final recovery = await metadata.beginRecoverySession();
    try {
      final database = locator<SqliteDatabase>();
      await database.transaction(() async {
        await database.delete(database.labels).go();
        await database.delete(database.walletMetadataBackupStates).go();
      });
      expect(await labels.fetchAll(), isEmpty);

      final result = _unwrap(
        await recovery.recover(createdWalletRefs: walletIds),
      );
      expect(result.status, WalletMetadataRecoveryStatus.recovered);
    } finally {
      recovery.close();
    }

    final recovered = _unwrap(await labels.exportBip329LabelRecords());
    expect(recovered, hasLength(expected.length));
    expect(_portableLabels(recovered), _portableLabels(expected));

    await metadata.retryPendingBackup();
    if (fake != null) expect(fake.backupStoreCalls, hasLength(1));

    final deleted = await metadata.deleteRemoteBackup();
    expect(deleted, isA<Ok<void, WalletMetadataBackupFailure>>());
    if (fake != null) {
      expect(fake.backupDeleteCalls, hasLength(1));
      expect(
        fake.backupDeleteCalls.single.stream,
        BullnymBackupStream.walletMetadata,
      );
    }
  });
}
