import 'dart:async';

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_backup_section_provider.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('re-emits a contributor change observed during recovery', () async {
    final contributor = _Contributor();
    final provider = WalletMetadataBackupSectionProviderImpl(
      contributors: [contributor],
      restoringContributors: [contributor],
    );
    addTearDown(provider.dispose);

    var changeCount = 0;
    final changesSubscription = provider.changes.listen((_) => changeCount++);
    addTearDown(changesSubscription.cancel);

    final payload = const WalletMetadataSnapshotCodec().encodeSnapshot(
      WalletMetadataSnapshot(
        parentFingerprint: '73c5da0a',
        revision: 1,
        createdAt: 1,
        recordsHash: contributor.recordsHash,
        recordCount: 1,
        sections: [
          WalletMetadataSection(
            type: 'test',
            versions: [1],
            recordCount: 1,
            recordsHash: contributor.recordsHash,
          ),
        ],
        records: [contributor.record],
      ),
    );

    final recovery = provider.recoverSection(
      payload: payload,
      createdWalletRefs: {'default'},
    );
    await contributor.applyStarted.future;
    contributor.changesController.add(null);
    contributor.applyCompleted.complete();

    final result = await recovery;
    expect(result, isA<Ok<WalletMetadataRecoveryApplyResult, dynamic>>());
    await pumpEventQueue();
    expect(changeCount, 1);
  });

  test(
    'does not start metadata mutation after the recovery deadline',
    () async {
      final now = DateTime.utc(2026);
      final contributor = _Contributor();
      final provider = WalletMetadataBackupSectionProviderImpl(
        contributors: [contributor],
        restoringContributors: [contributor],
        clock: _FixedClock(now),
      );
      addTearDown(provider.dispose);

      final result = await provider.recoverSection(
        payload: '{}',
        createdWalletRefs: const {},
        deadline: now,
      );

      expect(result, isA<Err<dynamic, WalletMetadataBackupFailure>>());
      expect(contributor.applyStarted.isCompleted, isFalse);
    },
  );
}

final class _FixedClock implements Clock {
  final DateTime now;

  const _FixedClock(this.now);

  @override
  DateTime nowUtc() => now;
}

final class _Contributor
    implements WalletMetadataRestoringContributor, WalletMetadataChangeSource {
  final record = WalletMetadataRecord(
    type: 'test',
    version: 1,
    scope: const {},
    recordId: 'record',
    payload: const {},
  );
  final changesController = StreamController<void>.broadcast();
  final applyStarted = Completer<void>();
  final applyCompleted = Completer<void>();

  String get recordsHash =>
      const WalletMetadataSnapshotCodec().recordsHash([record]);

  @override
  Stream<void> get changes => changesController.stream;

  @override
  String get recordType => 'test';

  @override
  Set<int> get supportedVersions => {1};

  @override
  WalletMetadataRecordValidation validateRecord(WalletMetadataRecord value) {
    return WalletMetadataRecordValid(
      WalletMetadataImportIntent(contributorType: recordType, record: value),
    );
  }

  @override
  Future<Result<List<WalletMetadataRecord>, WalletMetadataBackupFailure>>
  exportRecords() async => Ok([record]);

  @override
  Future<
    Result<WalletMetadataContributorApplySummary, WalletMetadataBackupFailure>
  >
  applyIntents({
    required List<WalletMetadataImportIntent> intents,
    required WalletMetadataApplyContext context,
  }) async {
    applyStarted.complete();
    await applyCompleted.future;
    return Ok(
      WalletMetadataContributorApplySummary(
        contributorType: recordType,
        intendedCount: intents.length,
        restoredCount: intents.length,
        alreadyPresentCount: 0,
        preservedLocalConflictCount: 0,
        deferredMissingWalletCount: 0,
        localProjectionMatchesSnapshot: true,
      ),
    );
  }
}
