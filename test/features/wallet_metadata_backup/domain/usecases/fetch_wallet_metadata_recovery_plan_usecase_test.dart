import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/fetch_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queries during recovery without enabling future publication', () async {
    final graph = _FakeGraphRepository(_scan());
    final state = _FakeStateRepository(WalletMetadataBackupState.initial);
    final usecase = _usecase(state: state, graph: graph);

    final result = _requireOk(await _execute(usecase));

    expect(result.status, WalletMetadataRecoveryStatus.noSnapshotFound);
    expect(graph.fetchCount, 1);
    expect(state.updateCount, 0);
    expect(state.state.enabled, isFalse);
    expect(state.state.relayDisclosureAcknowledged, isFalse);
  });

  test('recovery consent does not enable future backup publication', () async {
    final graph = _FakeGraphRepository(_scan());
    final state = _FakeStateRepository(
      WalletMetadataBackupState.initial.acknowledgeRelayDisclosure(),
    );

    final result = _requireOk(
      await _execute(_usecase(state: state, graph: graph)),
    );

    expect(result.status, WalletMetadataRecoveryStatus.noSnapshotFound);
    expect(graph.fetchCount, 1);
    expect(state.state.enabled, isFalse);
    expect(state.state.canAttemptPublication, isFalse);
  });

  test(
    'distinguishes absence, unavailable relays, and incomplete roots',
    () async {
      final cases = [
        (scan: _scan(), status: WalletMetadataRecoveryStatus.noSnapshotFound),
        (
          scan: _scan(
            relayStatus: WalletMetadataRelayRootQueryStatus.unavailable,
          ),
          status: WalletMetadataRecoveryStatus.relaysUnavailable,
        ),
        (
          scan: _scan(
            failures: [
              _failure(
                id: '2' * 64,
                kind: WalletMetadataRootFailureKind.incompleteGraph,
                revision: 3,
              ),
            ],
          ),
          status: WalletMetadataRecoveryStatus.noCompleteSnapshot,
        ),
      ];

      for (final item in cases) {
        final result = _requireOk(
          await _execute(
            _usecase(
              state: _FakeStateRepository(_activeState()),
              graph: _FakeGraphRepository(item.scan),
            ),
          ),
        );

        expect(result.status, item.status);
        expect(result.plan, isNull);
      }
    },
  );

  test(
    'persists unsupported newer envelope without producing a plan',
    () async {
      final state = _FakeStateRepository(_activeState());
      final unsupported = _failure(
        id: '3' * 64,
        kind: WalletMetadataRootFailureKind.unsupportedEnvelope,
        envelopeVersion: 2,
        createdAt: 1200,
      );
      final usecase = _usecase(
        state: state,
        graph: _FakeGraphRepository(_scan(failures: [unsupported])),
      );

      final result = _requireOk(await _execute(usecase));

      expect(
        result.status,
        WalletMetadataRecoveryStatus.unsupportedNewerEnvelope,
      );
      expect(state.state.unsupportedNewerEnvelope?.rootEventId, '3' * 64);
      expect(state.state.unsupportedNewerEnvelope?.envelopeVersion, 2);
      expect(state.state.unsupportedNewerEnvelope?.observedAt, _now);
      expect(state.state.dirty, isTrue);
    },
  );

  test('builds owner-validated intents and retains unknown metadata', () async {
    final valid = _record('labels.bip329', 1, 'valid-label');
    final invalid = _record('labels.bip329', 1, 'invalid-label');
    final newerVersion = _record('labels.bip329', 2, 'future-label');
    final unknown = _record('future.coin_note', 4, 'note-1');
    final head = _head(
      records: [valid, invalid, newerVersion, unknown],
      sectionVersions: const {
        'labels.bip329': [1, 2],
        'future.coin_note': [4],
        'future.empty': [9],
      },
    );
    final contributor = _FakeContributor(
      recordType: 'labels.bip329',
      invalidRecordIds: const {'invalid-label'},
    );
    final usecase = _usecase(
      state: _FakeStateRepository(_activeState()),
      graph: _FakeGraphRepository(_scan(head: head)),
      contributors: [contributor],
    );

    final result = _requireOk(await _execute(usecase));

    expect(
      result.status,
      WalletMetadataRecoveryStatus.latestSnapshotWithUnsupportedMetadata,
    );
    final plan = result.plan!;
    expect(plan.isOlderRestore, isFalse);
    expect(plan.plannedRecordCount, 1);
    expect(plan.contributorPlans.single.contributorType, 'labels.bip329');
    expect(plan.contributorPlans.single.sectionVersions, [1]);
    expect(
      plan.contributorPlans.single.intents.single.record.recordId,
      'valid-label',
    );
    expect(plan.invalidRecords, hasLength(1));
    expect(
      plan.invalidRecords.single.reason,
      WalletMetadataRecordInvalidReason.invalidPayload,
    );
    expect(plan.unsupportedRecords.map((record) => record.recordId), [
      'note-1',
      'future-label',
    ]);
    expect(plan.unsupportedSections.map((section) => section.type), [
      'future.coin_note',
      'future.empty',
      'labels.bip329',
    ]);
    expect(contributor.validationCount, 2);
    expect(contributor.exportCount, 0);
  });

  test(
    'marks a complete fallback as older when a newer graph failed',
    () async {
      final head = _head(records: [_record('labels.bip329', 1, 'label')]);
      final newer = _failure(
        id: '8' * 64,
        kind: WalletMetadataRootFailureKind.incompleteGraph,
        revision: head.root.revision + 1,
        createdAt: head.rootEventCreatedAt + 1,
      );
      final result = _requireOk(
        await _execute(
          _usecase(
            state: _FakeStateRepository(_activeState()),
            graph: _FakeGraphRepository(_scan(head: head, failures: [newer])),
          ),
        ),
      );

      expect(result.status, WalletMetadataRecoveryStatus.olderSnapshot);
      expect(result.plan?.isOlderRestore, isTrue);
      expect(result.plan?.newerRootFailures.single.revision, 5);
    },
  );

  test(
    'partial relay coverage makes the selected graph an older restore',
    () async {
      final head = _head(records: [_record('labels.bip329', 1, 'label')]);
      final result = _requireOk(
        await _execute(
          _usecase(
            state: _FakeStateRepository(_activeState()),
            graph: _FakeGraphRepository(
              _scan(
                head: head,
                relayStatus: WalletMetadataRelayRootQueryStatus.partial,
              ),
            ),
          ),
        ),
      );

      expect(result.status, WalletMetadataRecoveryStatus.olderSnapshot);
      expect(result.plan?.relayCoverageComplete, isFalse);
    },
  );

  test(
    'an older plan with a newer unsupported root also blocks publication',
    () async {
      final head = _head(records: [_record('labels.bip329', 1, 'label')]);
      final unsupported = _failure(
        id: '9' * 64,
        kind: WalletMetadataRootFailureKind.unsupportedEnvelope,
        envelopeVersion: 3,
        createdAt: head.rootEventCreatedAt + 1,
      );
      final state = _FakeStateRepository(_activeState());
      final result = _requireOk(
        await _execute(
          _usecase(
            state: state,
            graph: _FakeGraphRepository(
              _scan(head: head, failures: [unsupported]),
            ),
          ),
        ),
      );

      expect(result.status, WalletMetadataRecoveryStatus.olderSnapshot);
      expect(result.plan?.isOlderRestore, isTrue);
      expect(state.state.unsupportedNewerEnvelope?.envelopeVersion, 3);
    },
  );

  test(
    'a latest intentional empty snapshot produces an empty ready plan',
    () async {
      final head = _head(
        records: const [],
        sectionVersions: const {
          'labels.bip329': [1],
        },
      );
      final result = _requireOk(
        await _execute(
          _usecase(
            state: _FakeStateRepository(_activeState()),
            graph: _FakeGraphRepository(_scan(head: head)),
          ),
        ),
      );

      expect(result.status, WalletMetadataRecoveryStatus.latestSnapshot);
      expect(result.plan?.selectedHead.records, isEmpty);
      expect(result.plan?.plannedRecordCount, 0);
      expect(result.plan?.contributorPlans.single.intents, isEmpty);
    },
  );

  test('rejects duplicate contributor type registration', () {
    final contributor = _FakeContributor(recordType: 'labels.bip329');

    expect(
      () => _usecase(
        state: _FakeStateRepository(_activeState()),
        graph: _FakeGraphRepository(_scan()),
        contributors: [contributor, contributor],
      ),
      throwsArgumentError,
    );
  });
}

FetchWalletMetadataRecoveryPlanUsecase _usecase({
  required _FakeStateRepository state,
  required _FakeGraphRepository graph,
  List<WalletMetadataContributor>? contributors,
}) {
  return FetchWalletMetadataRecoveryPlanUsecase(
    stateRepository: state,
    graphRepository: graph,
    contributors:
        contributors ?? [_FakeContributor(recordType: 'labels.bip329')],
    relayPolicy: const NostrRelayPolicyFacade(
      relayUrlsOverride: 'wss://relay.example',
    ),
    clock: const _FixedClock(_now),
  );
}

Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
_execute(FetchWalletMetadataRecoveryPlanUsecase usecase) {
  return usecase.execute(
    xprvBase58: 'xprv-not-used-by-fake',
    parentFingerprint: '627ef3a6',
  );
}

final class _FakeStateRepository
    implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state;
  int updateCount = 0;

  _FakeStateRepository(this.state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async => Ok(state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    updateCount++;
    state = update(state);
    return Ok(state);
  }
}

final class _FakeGraphRepository implements WalletMetadataGraphRepository {
  final WalletMetadataGraphScan scan;
  int fetchCount = 0;

  _FakeGraphRepository(this.scan);

  @override
  Future<Result<WalletMetadataGraphScan, WalletMetadataBackupFailure>> fetch({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
    fetchCount++;
    return Ok(scan);
  }
}

final class _FakeContributor implements WalletMetadataContributor {
  @override
  final String recordType;
  final Set<String> invalidRecordIds;
  int validationCount = 0;
  int exportCount = 0;

  _FakeContributor({
    required this.recordType,
    this.invalidRecordIds = const {},
  });

  @override
  Set<int> get supportedVersions => const {1};

  @override
  WalletMetadataRecordValidation validateRecord(WalletMetadataRecord record) {
    validationCount++;
    if (invalidRecordIds.contains(record.recordId)) {
      return const WalletMetadataRecordInvalid(
        WalletMetadataRecordInvalidReason.invalidPayload,
      );
    }
    return WalletMetadataRecordValid(
      WalletMetadataImportIntent(contributorType: recordType, record: record),
    );
  }

  @override
  Future<Result<List<WalletMetadataRecord>, WalletMetadataBackupFailure>>
  exportRecords() async {
    exportCount++;
    return const Ok([]);
  }
}

WalletMetadataGraphScan _scan({
  WalletMetadataRemoteHead? head,
  List<WalletMetadataRootFailureObservation> failures = const [],
  WalletMetadataRelayRootQueryStatus relayStatus =
      WalletMetadataRelayRootQueryStatus.complete,
}) {
  final observedTimes = [
    ?head?.rootEventCreatedAt,
    ...failures.map((failure) => failure.eventCreatedAt),
  ];
  return WalletMetadataGraphScan(
    relayObservations: [
      WalletMetadataRelayRootObservation(
        relayUrl: WalletMetadataRelayUrl('wss://relay.example'),
        status: relayStatus,
        authenticRootCount: head == null && failures.isEmpty
            ? 0
            : (head == null ? 0 : 1) + failures.length,
      ),
    ],
    completeHeads: [?head],
    failures: failures,
    highestObservedRootCreatedAt: observedTimes.isEmpty
        ? null
        : observedTimes.reduce((left, right) => left > right ? left : right),
  );
}

WalletMetadataRemoteHead _head({
  required List<WalletMetadataRecord> records,
  Map<String, List<int>>? sectionVersions,
}) {
  const codec = WalletMetadataSnapshotCodec();
  final sortedRecords = List<WalletMetadataRecord>.of(records)..sort();
  final versions =
      sectionVersions ??
      {
        for (final type in sortedRecords.map((record) => record.type).toSet())
          type: sortedRecords
              .where((record) => record.type == type)
              .map((record) => record.version)
              .toSet()
              .toList(growable: false),
      };
  final sections = versions.entries
      .map((entry) {
        final sectionRecords = sortedRecords
            .where((record) => record.type == entry.key)
            .toList(growable: false);
        return WalletMetadataSection(
          type: entry.key,
          versions: entry.value,
          recordCount: sectionRecords.length,
          recordsHash: codec.recordsHash(sectionRecords),
        );
      })
      .toList(growable: false);
  return WalletMetadataRemoteHead(
    rootEventId: '7' * 64,
    rootEventCreatedAt: 1000,
    highestObservedRootCreatedAt: 1000,
    canonicalContentHash: codec.contentHash(
      records: sortedRecords,
      sections: sections,
    ),
    root: WalletMetadataSnapshotRoot(
      parentFingerprint: '627ef3a6',
      snapshotId: '6' * 32,
      revision: 4,
      createdAt: 1000,
      recordsHash: codec.recordsHash(sortedRecords),
      recordCount: sortedRecords.length,
      sections: sections,
      chunks: sortedRecords.isEmpty
          ? const []
          : [
              WalletMetadataChunkReference(
                index: 0,
                eventId: '5' * 64,
                dTag: '4' * 64,
                recordCount: sortedRecords.length,
                ciphertextHash: '3' * 64,
              ),
            ],
    ),
    records: sortedRecords,
  );
}

WalletMetadataRecord _record(String type, int version, String recordId) {
  return WalletMetadataRecord(
    type: type,
    version: version,
    scope: const {'kind': 'global'},
    recordId: recordId,
    payload: {'value': recordId},
  );
}

WalletMetadataRootFailureObservation _failure({
  required String id,
  required WalletMetadataRootFailureKind kind,
  int createdAt = 1100,
  int? revision,
  int? envelopeVersion,
}) {
  return WalletMetadataRootFailureObservation(
    rootEventId: id,
    eventCreatedAt: createdAt,
    revision: revision,
    envelopeVersion: envelopeVersion,
    kind: kind,
  );
}

WalletMetadataBackupState _activeState() => WalletMetadataBackupState.initial
    .withEnabled(true)
    .acknowledgeRelayDisclosure();

WalletMetadataRecoveryResult _requireOk(
  Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

final class _FixedClock implements Clock {
  final int seconds;

  const _FixedClock(this.seconds);

  @override
  DateTime nowUtc() =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

const _now = 1300;
