import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart'
    as internal;
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/acknowledge_wallet_metadata_relay_disclosure_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/get_wallet_metadata_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps recovery internals opaque and applies only issued plans',
    () async {
      final stateRepository = _StateRepository();
      final guard = WalletMetadataPublicationGuard();
      final coordinator = WalletMetadataBackupCoordinator(
        markDirty: MarkWalletMetadataBackupDirtyUsecase(stateRepository),
        publishCurrent: () async => Ok(
          WalletMetadataPublishOutcome(
            status: WalletMetadataPublishStatus.notReady,
          ),
        ),
        guard: guard,
        sources: () => const <WalletMetadataChangeSource>[],
      );
      addTearDown(coordinator.dispose);

      final issuedPlan = _plan();
      internal.WalletMetadataRecoveryPlan? appliedPlan;
      Set<String>? appliedWalletRefs;
      var applyCount = 0;
      final facade = WalletMetadataBackupFacade(
        GetWalletMetadataBackupStateUsecase(stateRepository),
        SetWalletMetadataBackupEnabledUsecase(stateRepository),
        AcknowledgeWalletMetadataRelayDisclosureUsecase(stateRepository),
        MarkWalletMetadataBackupDirtyUsecase(stateRepository),
        coordinator,
        ({required xprvBase58, required parentFingerprint}) async {
          expect(xprvBase58, 'test-xprv');
          expect(parentFingerprint, '627ef3a6');
          return Ok(internal.WalletMetadataRecoveryResult.ready(issuedPlan));
        },
        ({required plan, required createdWalletRefs}) async {
          expect(guard.isPublicationSuppressed, isTrue);
          applyCount++;
          appliedPlan = plan;
          appliedWalletRefs = createdWalletRefs;
          return Ok(
            WalletMetadataRecoveryApplyResult(
              status: WalletMetadataRecoveryApplyStatus.olderIncomplete,
              contributorOutcomes: const [],
              unsupportedRecordCount: 1,
              unsupportedSectionCount: 1,
              invalidRecordCount: 0,
            ),
          );
        },
      );

      final fetched = _requireOk(
        await facade.fetchRecoveryPlan(
          xprvBase58: 'test-xprv',
          parentFingerprint: '627ef3a6',
        ),
      );

      expect(
        fetched.status,
        WalletMetadataRecoveryStatus.olderSnapshotWithUnsupportedMetadata,
      );
      expect(fetched.plan?.plannedRecordCount, 1);
      expect(fetched.plan?.unsupportedCount, 2);
      expect(fetched.plan?.invalidRecordCount, 0);
      expect(fetched.plan?.isOlderRestore, isTrue);

      final applied = await facade.applyRecoveryPlan(
        plan: fetched.plan!,
        createdWalletRefs: const {'wallet-main'},
      );

      expect(
        applied,
        isA<
          Ok<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
        >(),
      );
      expect(appliedPlan, same(issuedPlan));
      expect(appliedWalletRefs, const {'wallet-main'});
      expect(applyCount, 1);
      expect(guard.isPublicationSuppressed, isFalse);

      final rejected = await facade.applyRecoveryPlan(
        plan: const _ForeignPlan(),
        createdWalletRefs: const {},
      );

      expect(
        rejected,
        isA<
          Err<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
        >(),
      );
      expect(
        (rejected
                as Err<
                  WalletMetadataRecoveryApplyResult,
                  WalletMetadataBackupFailure
                >)
            .failure,
        isA<WalletMetadataBackupEncodingFailure>(),
      );
      expect(applyCount, 1);
    },
  );
}

internal.WalletMetadataRecoveryPlan _plan() {
  const codec = WalletMetadataSnapshotCodec();
  final supported = WalletMetadataRecord(
    type: 'labels.bip329',
    version: 1,
    scope: const {'kind': 'global'},
    recordId: 'label-1',
    payload: const {'type': 'tx', 'ref': '0', 'label': 'label'},
  );
  final unsupported = WalletMetadataRecord(
    type: 'future.metadata',
    version: 2,
    scope: const {'kind': 'global'},
    recordId: 'future-1',
    payload: const {'value': true},
  );
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
      versions: const [2],
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
    highestObservedRootCreatedAt: 1100,
    canonicalContentHash: codec.contentHash(
      records: records,
      sections: sections,
    ),
    root: root,
    records: records,
  );
  return internal.WalletMetadataRecoveryPlan(
    selectedHead: head,
    contributorPlans: [
      internal.WalletMetadataContributorImportPlan(
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
    newerRootFailures: [
      WalletMetadataRootFailureObservation(
        rootEventId: '8' * 64,
        eventCreatedAt: 1100,
        revision: 5,
        kind: WalletMetadataRootFailureKind.incompleteGraph,
      ),
    ],
    relayCoverageComplete: true,
  );
}

WalletMetadataRecoveryResult _requireOk(
  Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected recovery result, got ${failure.runtimeType}',
    ),
  };
}

final class _StateRepository implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state = WalletMetadataBackupState.initial;

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async => Ok(state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    state = update(state);
    return Ok(state);
  }
}

final class _ForeignPlan implements WalletMetadataRecoveryPlan {
  const _ForeignPlan();

  @override
  int get invalidRecordCount => 0;

  @override
  bool get isOlderRestore => false;

  @override
  int get plannedRecordCount => 0;

  @override
  int get unsupportedCount => 0;
}
