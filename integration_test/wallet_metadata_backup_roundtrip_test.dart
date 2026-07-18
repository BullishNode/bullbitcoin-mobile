import 'package:bb_mobile/core/failures/failure.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/core/wallet/domain/entities/frozen_wallet_outpoint.dart';
import 'package:bb_mobile/core/wallet/domain/repositories/wallet_utxo_repository.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/create_default_wallets_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_frozen_wallet_outpoints_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/get_wallet_preferences_usecase.dart';
import 'package:bb_mobile/core/wallet/domain/usecases/update_wallet_behavior_usecase.dart';
import 'package:bb_mobile/features/bullnym/domain/bullnym_backup_blob.dart';
import 'package:bb_mobile/features/keychain_manifest/public/keychain_manifest_facade.dart';
import 'package:bb_mobile/features/labels/labels_facade.dart';
import 'package:bb_mobile/features/test_wallet_backup/domain/usecases/get_mnemonic_from_fingerprint_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/locator.dart';
import 'package:bb_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_bullnym_client.dart';
import 'support/override_wallet_metadata_backup_remote.dart';
import 'support/wipe_app_state.dart';

const _liveBullnym = bool.fromEnvironment('BULLNYM_BACKUP_LIVE');
const _labelCount = 1000;
const _frozenTxId =
    'f00000000000000000000000000000000000000000000000000000000000000f';
const _frozenVout = 7;

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

  test('Bullnym restores every wallet metadata class after a same-seed '
      'local-state reset, then honors deletion', () async {
    final FakeBullnymClient? fake;
    if (_liveBullnym) {
      fake = null;
    } else {
      fake = FakeBullnymClient();
      await overrideWalletMetadataBackupRemote(locator, fake);
    }

    await wipeAppState(locator);
    final wallets = await locator<CreateDefaultWalletsUsecase>().execute();
    final walletIds = wallets.map((wallet) => wallet.id).toSet();
    expect(walletIds, isNotEmpty);
    final testWallet = wallets.first;
    final (
      mnemonicWords,
      _,
    ) = await locator<GetMnemonicFromFingerprintUsecase>().execute(
      testWallet.masterFingerprint,
    );

    final metadata = locator<WalletMetadataBackupFacade>();
    final labels = locator<LabelsFacade>();
    var remotePublished = false;

    try {
      _unwrap(await metadata.setEnabled(true));

      final expectedLabels = _labels(_labelCount);
      final restoredLocally = _unwrap(
        await labels.restoreBip329LabelRecords(expectedLabels),
      );
      expect(restoredLocally.restoredCount, expectedLabels.length);

      await locator<UpdateWalletBehaviorUsecase>().execute(
        walletId: testWallet.id,
        hideOnHome: true,
        autoSweepEnabled: true,
      );
      await locator<WalletUtxoRepository>().freezeUtxos(
        walletId: testWallet.id,
        outpoints: const [(txId: _frozenTxId, vout: _frozenVout)],
      );

      final published = _unwrap(await metadata.backupNow());
      expect(published.status, WalletMetadataPublishStatus.stored);
      expect(published.remoteGeneration, greaterThan(0));
      remotePublished = true;
      if (fake != null) {
        expect(fake.backupStoreCalls, isNotEmpty);
        expect(
          fake.backupStoreCalls.every(
            (request) => request.stream == BullnymBackupStream.walletMetadata,
          ),
          isTrue,
        );
        expect(
          fake.backupStoreCalls.last.stream,
          BullnymBackupStream.walletMetadata,
        );
      } else {
        final absentManifest = await locator<KeychainManifestFacade>()
            .fetchRemoteImportPlan();
        expect(
          absentManifest.status,
          KeychainManifestRemoteImportStatus.absent,
        );
      }

      await wipeAppState(locator);
      expect(await labels.fetchAll(), isEmpty);
      expect(
        await locator<GetFrozenWalletOutpointsUsecase>().execute(),
        isEmpty,
      );

      final recreatedWallets = await locator<CreateDefaultWalletsUsecase>()
          .execute(mnemonicWords: mnemonicWords);
      final recreatedWalletIds = recreatedWallets
          .map((wallet) => wallet.id)
          .toSet();
      expect(recreatedWalletIds, walletIds);

      final recovery = await metadata.beginRecoverySession();
      try {
        final result = _unwrap(
          await recovery.recover(createdWalletRefs: recreatedWalletIds),
        );
        expect(result.status, WalletMetadataRecoveryStatus.recovered);
      } finally {
        recovery.close();
      }

      final recoveredLabels = _unwrap(await labels.exportBip329LabelRecords());
      expect(recoveredLabels, hasLength(expectedLabels.length));
      expect(_portableLabels(recoveredLabels), _portableLabels(expectedLabels));

      final preferences = _unwrap(
        await locator<GetWalletPreferencesUsecase>().execute(),
      );
      final recoveredPreferences = preferences.singleWhere(
        (entry) => entry.walletRef == testWallet.id,
      );
      expect(recoveredPreferences.hideOnHome, isTrue);
      expect(recoveredPreferences.autoSweepEnabled, isTrue);

      final recoveredFreezes = await locator<GetFrozenWalletOutpointsUsecase>()
          .execute();
      expect(
        recoveredFreezes,
        contains(
          isA<FrozenWalletOutpoint>()
              .having((freeze) => freeze.walletId, 'walletId', testWallet.id)
              .having((freeze) => freeze.txId, 'txId', _frozenTxId)
              .having((freeze) => freeze.vout, 'vout', _frozenVout),
        ),
      );

      await metadata.retryPendingBackup();

      _unwrap(await metadata.setEnabled(false));
      final deleted = await metadata.deleteRemoteBackup();
      expect(deleted, isA<Ok<void, WalletMetadataBackupFailure>>());
      remotePublished = false;
      if (fake != null) {
        expect(fake.backupDeleteCalls, hasLength(1));
        expect(
          fake.backupDeleteCalls.single.stream,
          BullnymBackupStream.walletMetadata,
        );
      }

      final postDeleteRecovery = await metadata.beginRecoverySession();
      try {
        final result = _unwrap(
          await postDeleteRecovery.recover(
            createdWalletRefs: recreatedWalletIds,
          ),
        );
        expect(result.status, WalletMetadataRecoveryStatus.noSnapshotFound);
      } finally {
        postDeleteRecovery.close();
      }
    } finally {
      if (remotePublished) {
        _unwrap(await metadata.setEnabled(false));
        final deleted = await metadata.deleteRemoteBackup();
        expect(deleted, isA<Ok<void, WalletMetadataBackupFailure>>());
      }
      await wipeAppState(locator);
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
