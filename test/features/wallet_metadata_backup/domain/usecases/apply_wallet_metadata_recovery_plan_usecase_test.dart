import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_root.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/apply_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_root_port.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an exact latest apply records the selected head clean', () async {
    final alpha = _FakeRestoringContributor('alpha');
    final beta = _FakeRestoringContributor('beta');
    final state = _FakeStateRepository(_activeState());
    final plan = _plan(types: const ['alpha', 'beta']);

    final result = _requireOk(
      await _usecase(state, [
        alpha,
        beta,
      ]).execute(plan: plan, createdWalletRefs: const {}),
    );

    expect(result.status, WalletMetadataRecoveryApplyStatus.latestComplete);
    expect(result.publicationBlocked, isFalse);
    expect(result.restoredCount, 2);
    expect(alpha.applyCount, 1);
    expect(beta.applyCount, 1);
    expect(state.updateCount, 2);
    expect(state.state.dirty, isFalse);
    expect(state.state.recoveryBlock, isNull);
    expect(
      state.state.verifiedHead?.rootEventId,
      plan.selectedHead.rootEventId,
    );
    expect(
      state.state.verifiedHead?.canonicalContentHash,
      plan.selectedHead.canonicalContentHash,
    );
  });

  test('one owner failure does not roll back another owner', () async {
    final failed = _FakeRestoringContributor('alpha', failApply: true);
    final restored = _FakeRestoringContributor('beta');
    final state = _FakeStateRepository(_activeState());

    final result = _requireOk(
      await _usecase(state, [failed, restored]).execute(
        plan: _plan(types: const ['alpha', 'beta']),
        createdWalletRefs: const {},
      ),
    );

    expect(result.status, WalletMetadataRecoveryApplyStatus.latestIncomplete);
    expect(result.publicationBlocked, isTrue);
    expect(result.contributorOutcomes.first.storageFailed, isTrue);
    expect(restored.applyCount, 1);
    expect(
      state.state.recoveryBlock?.reason,
      WalletMetadataRecoveryBlockReason.incompleteApply,
    );
    expect(state.state.canAttemptPublication, isFalse);
  });

  test('an exact older restore remains blocked from publication', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final state = _FakeStateRepository(_activeState());

    final result = _requireOk(
      await _usecase(state, [contributor]).execute(
        plan: _plan(types: const ['alpha'], relayCoverageComplete: false),
        createdWalletRefs: const {},
      ),
    );

    expect(result.status, WalletMetadataRecoveryApplyStatus.olderComplete);
    expect(result.publicationBlocked, isTrue);
    expect(
      state.state.recoveryBlock?.reason,
      WalletMetadataRecoveryBlockReason.olderSnapshot,
    );
    expect(state.state.dirty, isTrue);
  });

  test('unsupported future metadata keeps a latest apply blocked', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final state = _FakeStateRepository(_activeState());

    final result = _requireOk(
      await _usecase(state, [contributor]).execute(
        plan: _planWithUnsupportedMetadata(),
        createdWalletRefs: const {},
      ),
    );

    expect(result.status, WalletMetadataRecoveryApplyStatus.latestIncomplete);
    expect(result.unsupportedRecordCount, 1);
    expect(result.unsupportedSectionCount, 1);
    expect(result.unsupportedCount, 2);
    expect(result.publicationBlocked, isTrue);
    expect(
      state.state.recoveryBlock?.reason,
      WalletMetadataRecoveryBlockReason.incompleteApply,
    );
  });

  test('a forged plan fails preflight before state or owner writes', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final state = _FakeStateRepository(_activeState());
    final selected = _record('alpha', 'record-alpha');
    final forged = WalletMetadataRecord(
      type: selected.type,
      version: selected.version,
      scope: selected.scope,
      recordId: selected.recordId,
      payload: const {'value': 'forged'},
    );
    final plan = _plan(
      types: const ['alpha'],
      selectedRecords: [selected],
      plannedRecords: [forged],
    );

    final result = await _usecase(state, [
      contributor,
    ]).execute(plan: plan, createdWalletRefs: const {});

    expect(
      result,
      isA<
        Err<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
      >(),
    );
    expect(state.updateCount, 0);
    expect(contributor.applyCount, 0);
  });

  test('an owner change rejects a stale plan before state writes', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final state = _FakeStateRepository(_activeState());

    final result =
        await _usecase(state, [
          contributor,
        ], rootPort: _FakeRootPort(parentFingerprint: 'deadbeef')).execute(
          plan: _plan(types: const ['alpha']),
          createdWalletRefs: const {},
        );

    expect(
      result,
      isA<
        Err<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
      >(),
    );
    expect(
      (result
              as Err<
                WalletMetadataRecoveryApplyResult,
                WalletMetadataBackupFailure
              >)
          .failure,
      isA<WalletMetadataBackupKeyFailure>(),
    );
    expect(state.updateCount, 0);
    expect(contributor.applyCount, 0);
  });

  test('a plan cannot omit a selected owned record', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final state = _FakeStateRepository(_activeState());
    final first = _record('alpha', 'record-one');
    final second = _record('alpha', 'record-two');

    final result = await _usecase(state, [contributor]).execute(
      plan: _plan(
        types: const ['alpha'],
        selectedRecords: [first, second],
        plannedRecords: [first],
      ),
      createdWalletRefs: const {},
    );

    expect(
      result,
      isA<
        Err<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
      >(),
    );
    expect(state.updateCount, 0);
    expect(contributor.applyCount, 0);
  });

  test(
    'a final state write failure leaves apply-in-progress persisted',
    () async {
      final contributor = _FakeRestoringContributor('alpha');
      final state = _FakeStateRepository(_activeState(), failUpdate: 2);

      final result = await _usecase(state, [contributor]).execute(
        plan: _plan(types: const ['alpha']),
        createdWalletRefs: const {},
      );

      expect(
        result,
        isA<
          Err<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
        >(),
      );
      expect(contributor.applyCount, 1);
      expect(
        state.state.recoveryBlock?.reason,
        WalletMetadataRecoveryBlockReason.applyInProgress,
      );
      expect(state.state.canAttemptPublication, isFalse);
    },
  );

  test('a local newer verified head cannot be regressed by apply', () async {
    final contributor = _FakeRestoringContributor('alpha');
    final current = _activeState().recordVerifiedHead(
      head: WalletMetadataBackupVerifiedHead(
        rootEventId: '9' * 64,
        snapshotRevision: 10,
        canonicalContentHash: '8' * 64,
        verifiedAt: 900,
      ),
      expectedDirtyRevision: _activeState().dirtyRevision,
    );
    final state = _FakeStateRepository(current);

    final result = _requireOk(
      await _usecase(state, [contributor]).execute(
        plan: _plan(types: const ['alpha']),
        createdWalletRefs: const {},
      ),
    );

    expect(result.status, WalletMetadataRecoveryApplyStatus.latestIncomplete);
    expect(state.state.verifiedHead?.snapshotRevision, 10);
    expect(
      state.state.recoveryBlock?.reason,
      WalletMetadataRecoveryBlockReason.incompleteApply,
    );
  });
}

ApplyWalletMetadataRecoveryPlanUsecase _usecase(
  WalletMetadataBackupStateRepository state,
  List<WalletMetadataRestoringContributor> contributors, {
  WalletMetadataBackupRootPort? rootPort,
}) {
  return ApplyWalletMetadataRecoveryPlanUsecase(
    rootPort ?? _FakeRootPort(),
    stateRepository: state,
    contributors: contributors,
    clock: const _FixedClock(2000),
  );
}

WalletMetadataRecoveryPlan _plan({
  required List<String> types,
  bool relayCoverageComplete = true,
  List<WalletMetadataRecord>? selectedRecords,
  List<WalletMetadataRecord>? plannedRecords,
}) {
  const codec = WalletMetadataSnapshotCodec();
  final records = List<WalletMetadataRecord>.of(
    selectedRecords ?? types.map((type) => _record(type, 'record-$type')),
  )..sort();
  final planned = List<WalletMetadataRecord>.of(plannedRecords ?? records);
  final sections = types
      .map((type) {
        final sectionRecords = records
            .where((record) => record.type == type)
            .toList(growable: false);
        return WalletMetadataSection(
          type: type,
          versions: const [1],
          recordCount: sectionRecords.length,
          recordsHash: codec.recordsHash(sectionRecords),
        );
      })
      .toList(growable: false);
  final head = WalletMetadataRemoteHead(
    rootEventId: '7' * 64,
    rootEventCreatedAt: 1000,
    highestObservedRootCreatedAt: 1000,
    canonicalContentHash: codec.contentHash(
      records: records,
      sections: sections,
    ),
    root: WalletMetadataSnapshotRoot(
      parentFingerprint: '627ef3a6',
      snapshotId: '6' * 32,
      revision: 4,
      createdAt: 1000,
      recordsHash: codec.recordsHash(records),
      recordCount: records.length,
      sections: sections,
      chunks: records.isEmpty
          ? const []
          : [
              WalletMetadataChunkReference(
                index: 0,
                eventId: '5' * 64,
                dTag: '4' * 64,
                recordCount: records.length,
                ciphertextHash: '3' * 64,
              ),
            ],
    ),
    records: records,
  );
  return WalletMetadataRecoveryPlan(
    selectedHead: head,
    contributorPlans: types
        .map((type) {
          final typeRecords = planned.where((record) => record.type == type);
          return WalletMetadataContributorImportPlan(
            contributorType: type,
            sectionVersions: const [1],
            intents: typeRecords
                .map(
                  (record) => WalletMetadataImportIntent(
                    contributorType: type,
                    record: record,
                  ),
                )
                .toList(growable: false),
          );
        })
        .toList(growable: false),
    unsupportedRecords: const [],
    unsupportedSections: const [],
    invalidRecords: const [],
    newerRootFailures: const [],
    relayCoverageComplete: relayCoverageComplete,
  );
}

WalletMetadataRecoveryPlan _planWithUnsupportedMetadata() {
  const codec = WalletMetadataSnapshotCodec();
  final supported = _record('alpha', 'record-alpha');
  final unsupported = _record('future.metadata', 'record-future');
  final records = [supported, unsupported]..sort();
  final sections = [
    WalletMetadataSection(
      type: supported.type,
      versions: const [1],
      recordCount: 1,
      recordsHash: codec.recordsHash([supported]),
    ),
    WalletMetadataSection(
      type: unsupported.type,
      versions: const [1],
      recordCount: 1,
      recordsHash: codec.recordsHash([unsupported]),
    ),
  ];
  final root = WalletMetadataSnapshotRoot(
    parentFingerprint: '627ef3a6',
    snapshotId: '6' * 32,
    revision: 4,
    createdAt: 1000,
    recordsHash: codec.recordsHash(records),
    recordCount: records.length,
    sections: sections,
    chunks: [
      WalletMetadataChunkReference(
        index: 0,
        eventId: '5' * 64,
        dTag: '4' * 64,
        recordCount: records.length,
        ciphertextHash: '3' * 64,
      ),
    ],
  );
  final head = WalletMetadataRemoteHead(
    rootEventId: '7' * 64,
    rootEventCreatedAt: 1000,
    highestObservedRootCreatedAt: 1000,
    canonicalContentHash: codec.contentHash(
      records: records,
      sections: sections,
    ),
    root: root,
    records: records,
  );
  return WalletMetadataRecoveryPlan(
    selectedHead: head,
    contributorPlans: [
      WalletMetadataContributorImportPlan(
        contributorType: supported.type,
        sectionVersions: const [1],
        intents: [
          WalletMetadataImportIntent(
            contributorType: supported.type,
            record: supported,
          ),
        ],
      ),
    ],
    unsupportedRecords: [unsupported],
    unsupportedSections: [sections.last],
    invalidRecords: const [],
    newerRootFailures: const [],
    relayCoverageComplete: true,
  );
}

WalletMetadataRecord _record(String type, String recordId) {
  return WalletMetadataRecord(
    type: type,
    version: 1,
    scope: const {'kind': 'global'},
    recordId: recordId,
    payload: {'value': recordId},
  );
}

WalletMetadataBackupState _activeState() => WalletMetadataBackupState.initial
    .withEnabled(true)
    .acknowledgeRelayDisclosure();

WalletMetadataRecoveryApplyResult _requireOk(
  Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

final class _FakeRestoringContributor
    implements WalletMetadataRestoringContributor {
  @override
  final String recordType;
  final bool failApply;
  int applyCount = 0;

  _FakeRestoringContributor(this.recordType, {this.failApply = false});

  @override
  Set<int> get supportedVersions => const {1};

  @override
  WalletMetadataRecordValidation validateRecord(WalletMetadataRecord record) {
    if (record.type != recordType || record.version != 1) {
      return const WalletMetadataRecordInvalid(
        WalletMetadataRecordInvalidReason.unsupportedTypeOrVersion,
      );
    }
    return WalletMetadataRecordValid(
      WalletMetadataImportIntent(contributorType: recordType, record: record),
    );
  }

  @override
  Future<
    Result<WalletMetadataContributorApplySummary, WalletMetadataBackupFailure>
  >
  applyIntents({
    required List<WalletMetadataImportIntent> intents,
    required WalletMetadataApplyContext context,
  }) async {
    applyCount++;
    if (failApply) {
      return Err(WalletMetadataBackupContributorFailure(recordType));
    }
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

  @override
  Future<Result<List<WalletMetadataRecord>, WalletMetadataBackupFailure>>
  exportRecords() async => const Ok([]);
}

final class _FakeStateRepository
    implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state;
  final int? failUpdate;
  int updateCount = 0;

  _FakeStateRepository(this.state, {this.failUpdate});

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async => Ok(state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    updateCount++;
    if (updateCount == failUpdate) {
      return const Err(WalletMetadataBackupStorageFailure());
    }
    state = update(state);
    return Ok(state);
  }
}

final class _FakeRootPort implements WalletMetadataBackupRootPort {
  final String parentFingerprint;

  _FakeRootPort({this.parentFingerprint = '627ef3a6'});

  @override
  Future<Result<WalletMetadataBackupRoot, WalletMetadataBackupFailure>>
  deriveLocalRoot() async {
    return Ok(
      WalletMetadataBackupRoot(
        xprvBase58: 'test-xprv',
        parentFingerprint: parentFingerprint,
      ),
    );
  }
}

final class _FixedClock implements Clock {
  final int seconds;

  const _FixedClock(this.seconds);

  @override
  DateTime nowUtc() =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}
