import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_codec.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_composition_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_safe_head_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('activation and safe-head gates', () {
    test('does no network work while off, unconsented, or clean', () async {
      final clean = _activeState().recordNoPublicationNeeded(
        expectedDirtyRevision: 1,
      );
      final states = [
        WalletMetadataBackupState.initial,
        WalletMetadataBackupState.initial.withEnabled(true),
        clean,
      ];

      for (final state in states) {
        final harness = _Harness(state: state);

        final outcome = _requireOk(await harness.execute());

        expect(outcome.status, WalletMetadataPublishStatus.notReady);
        expect(harness.safeHead.fetchCount, 0);
        expect(harness.snapshot.buildCount, 0);
        expect(harness.relay.publishCount, 0);
        expect(harness.state.updateCount, 0);
      }
    });

    test('persisted unsupported state blocks before network access', () async {
      final state = _activeState().recordUnsupportedNewerEnvelope(
        _unsupportedEnvelope(),
      );
      final harness = _Harness(state: state);

      final failure = _requireFailure(await harness.execute());

      expect(failure, isA<WalletMetadataBackupUpdateRequiredFailure>());
      expect(harness.safeHead.fetchCount, 0);
      expect(harness.state.updateCount, 0);
    });

    test('a concurrent disable blocks before relay access', () async {
      final harness = _Harness();
      harness.state.stateBeforeNextUpdate = harness.state.state.withEnabled(
        false,
      );

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.notReady);
      expect(harness.safeHead.fetchCount, 0);
      expect(harness.snapshot.buildCount, 0);
      expect(harness.relay.publishCount, 0);
      expect(harness.state.state.lastAttemptedAt, isNull);
    });

    test('distinguishes unavailable and incomplete current heads', () async {
      final cases = <WalletMetadataSafeHeadResult, Type>{
        const WalletMetadataSafeHeadUnavailable():
            WalletMetadataBackupRelayFailure,
        const WalletMetadataSafeHeadIncomplete():
            WalletMetadataBackupRemoteHeadFailure,
      };

      for (final entry in cases.entries) {
        final harness = _Harness(safeHeadResult: entry.key);

        final failure = _requireFailure(await harness.execute());

        expect(failure.runtimeType, entry.value);
        expect(harness.state.state.lastAttemptedAt, _now);
        expect(harness.snapshot.buildCount, 0);
        expect(harness.relay.publishCount, 0);
      }
    });

    test(
      'persists an authenticated unsupported head before blocking',
      () async {
        final unsupported = _unsupportedEnvelope();
        final harness = _Harness(
          safeHeadResult: WalletMetadataSafeHeadUnsupported(unsupported),
        );

        final failure = _requireFailure(await harness.execute());

        expect(failure, isA<WalletMetadataBackupUpdateRequiredFailure>());
        expect(
          harness.state.state.unsupportedNewerEnvelope?.rootEventId,
          unsupported.rootEventId,
        );
        expect(harness.state.state.dirty, isTrue);
        expect(harness.snapshot.buildCount, 0);
      },
    );
  });

  group('composition and publication', () {
    test(
      'one failed contributor aborts before snapshot construction',
      () async {
        final first = _FakeContributor(
          recordType: 'labels.bip329',
          records: [_record('labels.bip329', 1, 'label-1', 'label')],
        );
        final failed = _FakeContributor(
          recordType: 'wallet.utxo_freeze',
          failure: const WalletMetadataBackupContributorFailure(
            'wallet.utxo_freeze',
          ),
        );
        final harness = _Harness(contributors: [first, failed]);

        final failure = _requireFailure(await harness.execute());

        expect(failure, isA<WalletMetadataBackupContributorFailure>());
        expect(first.exportCount, 1);
        expect(failed.exportCount, 1);
        expect(harness.snapshot.buildCount, 0);
        expect(harness.relay.publishCount, 0);
        expect(harness.state.state.dirty, isTrue);
      },
    );

    test('initial all-empty inventory is clean without publishing', () async {
      final harness = _Harness(
        contributors: [
          _FakeContributor(recordType: 'labels.bip329', records: const []),
          _FakeContributor(recordType: 'wallet.preferences', records: const []),
        ],
      );

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.initialEmpty);
      expect(harness.snapshot.buildCount, 0);
      expect(harness.relay.publishCount, 0);
      expect(harness.state.state.dirty, isFalse);
      expect(harness.state.state.verifiedHead, isNull);
    });

    test('an initial-empty race leaves the newer mutation dirty', () async {
      late _Harness harness;
      final contributor = _FakeContributor(
        recordType: 'labels.bip329',
        records: const [],
        onExport: () => harness.state.state = harness.state.state.markDirty(),
      );
      harness = _Harness(contributors: [contributor]);

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.initialEmpty);
      expect(harness.state.state.dirty, isTrue);
      expect(harness.state.state.dirtyRevision, 2);
    });

    test('same complete remote content is a verified no-op', () async {
      final record = _record('labels.bip329', 1, 'label-1', 'same');
      final remote = _remoteHead(
        records: [record],
        revision: 7,
        createdAt: 900,
      );
      final harness = _Harness(
        safeHeadResult: WalletMetadataSafeHeadCompatible(remote),
        contributors: [
          _FakeContributor(recordType: 'labels.bip329', records: [record]),
        ],
      );

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.unchanged);
      expect(harness.snapshot.buildCount, 0);
      expect(harness.relay.publishCount, 0);
      expect(harness.state.state.dirty, isFalse);
      expect(harness.state.state.verifiedHead?.rootEventId, remote.rootEventId);
      expect(harness.state.state.verifiedHead?.snapshotRevision, 7);
      expect(
        harness.state.state.verifiedHead?.canonicalContentHash,
        const WalletMetadataSnapshotCodec().contentHash(
          records: remote.records,
          sections: remote.root.sections,
        ),
      );
    });

    test(
      'an added empty supported version is not treated as unchanged',
      () async {
        final record = _record('labels.bip329', 1, 'label-1', 'same');
        final remote = _remoteHead(
          records: [record],
          revision: 7,
          createdAt: 900,
        );
        final harness = _Harness(
          safeHeadResult: WalletMetadataSafeHeadCompatible(remote),
          contributors: [
            _FakeContributor(
              recordType: 'labels.bip329',
              supportedVersions: const {1, 2},
              records: [record],
            ),
          ],
        );

        final outcome = _requireOk(await harness.execute());

        expect(outcome.status, WalletMetadataPublishStatus.verified);
        expect(harness.snapshot.lastRevision, 8);
        expect(harness.snapshot.lastSections.single.versions, [1, 2]);
      },
    );

    test(
      'preserves unknown types and unsupported versions on republish',
      () async {
        final oldKnown = _record('labels.bip329', 1, 'old', 'old');
        final newerKnown = _record('labels.bip329', 2, 'v2', 'opaque-v2');
        final unknown = _record('future.coin_note', 4, 'note-1', 'opaque');
        final local = _record('labels.bip329', 1, 'local', 'local');
        final remote = _remoteHead(
          records: [oldKnown, newerKnown, unknown],
          revision: 4,
          createdAt: 900,
          sectionVersions: const {
            'labels.bip329': [1, 2],
            'future.coin_note': [4],
            'future.empty': [9],
          },
        );
        final harness = _Harness(
          safeHeadResult: WalletMetadataSafeHeadCompatible(remote),
          contributors: [
            _FakeContributor(recordType: 'labels.bip329', records: [local]),
          ],
        );

        _requireOk(await harness.execute());

        expect(harness.snapshot.lastRecords.map((record) => record.recordId), [
          'note-1',
          'local',
          'v2',
        ]);
        expect(harness.snapshot.lastSections.map((section) => section.type), [
          'future.coin_note',
          'future.empty',
          'labels.bip329',
        ]);
        expect(
          harness.snapshot.lastSections
              .singleWhere((section) => section.type == 'future.empty')
              .recordCount,
          0,
        );
      },
    );

    test(
      'allocates revision and event time above local and remote heads',
      () async {
        final remoteRecord = _record('labels.bip329', 1, 'old', 'remote');
        final localRecord = _record('labels.bip329', 1, 'new', 'local');
        final remote = _remoteHead(
          records: [remoteRecord],
          revision: 10,
          createdAt: 1500,
          highestObservedCreatedAt: 2000,
        );
        final localHead = WalletMetadataBackupVerifiedHead(
          rootEventId: '9' * 64,
          snapshotRevision: 12,
          canonicalContentHash: '8' * 64,
          verifiedAt: 800,
        );
        final harness = _Harness(
          state: _activeState(head: localHead),
          safeHeadResult: WalletMetadataSafeHeadCompatible(remote),
          contributors: [
            _FakeContributor(
              recordType: 'labels.bip329',
              records: [localRecord],
            ),
          ],
          now: 1800,
        );

        _requireOk(await harness.execute());

        expect(harness.snapshot.lastRevision, 13);
        expect(harness.snapshot.lastCreatedAt, 2001);
      },
    );

    test(
      'blocks revision and timestamp overflow before snapshot creation',
      () async {
        final max = WalletMetadataBackupLimits.maxSignedInt64;
        final cases = [
          _Harness(
            state: _activeState(
              head: WalletMetadataBackupVerifiedHead(
                rootEventId: '9' * 64,
                snapshotRevision: max,
                canonicalContentHash: '8' * 64,
                verifiedAt: 1,
              ),
            ),
          ),
          _Harness(
            safeHeadResult: WalletMetadataSafeHeadCompatible(
              _remoteHead(
                records: [_record('labels.bip329', 1, 'old', 'remote')],
                revision: 2,
                createdAt: max,
                highestObservedCreatedAt: max,
              ),
            ),
          ),
        ];

        for (final harness in cases) {
          final failure = _requireFailure(await harness.execute());
          expect(failure, isA<WalletMetadataBackupClockFailure>());
          expect(harness.snapshot.buildCount, 0);
        }
      },
    );
  });

  group('relay outcomes and dirty races', () {
    test('no accepted root leaves the snapshot dirty', () async {
      final harness = _Harness(
        relayStatus: WalletMetadataRelayReplicaStatus.rootNotAccepted,
      );

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.notAccepted);
      expect(harness.state.state.lastAcceptedAt, isNull);
      expect(harness.state.state.verifiedHead, isNull);
      expect(harness.state.state.dirty, isTrue);
    });

    test(
      'accepted but unverified root records acceptance and stays dirty',
      () async {
        final harness = _Harness(
          relayStatus: WalletMetadataRelayReplicaStatus.acceptedUnverified,
        );

        final outcome = _requireOk(await harness.execute());

        expect(outcome.status, WalletMetadataPublishStatus.acceptedUnverified);
        expect(outcome.acceptedReplicaCount, 1);
        expect(outcome.verifiedReplicaCount, 0);
        expect(harness.state.state.lastAcceptedAt, _now);
        expect(harness.state.state.verifiedHead, isNull);
        expect(harness.state.state.dirty, isTrue);
      },
    );

    test(
      'verified root records the content head and clears captured work',
      () async {
        final harness = _Harness();

        final outcome = _requireOk(await harness.execute());

        expect(outcome.status, WalletMetadataPublishStatus.verified);
        expect(outcome.acceptedReplicaCount, 1);
        expect(outcome.verifiedReplicaCount, 1);
        expect(harness.state.state.lastAcceptedAt, _now);
        expect(harness.state.state.dirty, isFalse);
        expect(
          harness.state.state.verifiedHead?.rootEventId,
          outcome.rootEventId,
        );
        expect(harness.state.state.verifiedHead?.snapshotRevision, 1);
        expect(
          harness.state.state.verifiedHead?.canonicalContentHash,
          const WalletMetadataSnapshotCodec().contentHash(
            records: harness.snapshot.lastRecords,
            sections: harness.snapshot.lastSections,
          ),
        );
      },
    );

    test('a mutation during relay publication survives verification', () async {
      late _Harness harness;
      harness = _Harness();
      harness.relay.onPublish = () {
        harness.state.state = harness.state.state.markDirty();
      };

      final outcome = _requireOk(await harness.execute());

      expect(outcome.status, WalletMetadataPublishStatus.verified);
      expect(harness.state.state.verifiedHead, isNotNull);
      expect(harness.state.state.dirty, isTrue);
      expect(harness.state.state.dirtyRevision, 2);
    });

    test(
      'an all-empty transition after a verified head is published',
      () async {
        final oldRecord = _record('labels.bip329', 1, 'old', 'old');
        final remote = _remoteHead(
          records: [oldRecord],
          revision: 5,
          createdAt: 900,
        );
        final localHead = WalletMetadataBackupVerifiedHead(
          rootEventId: remote.rootEventId,
          snapshotRevision: remote.root.revision,
          canonicalContentHash: const WalletMetadataSnapshotCodec().contentHash(
            records: remote.records,
            sections: remote.root.sections,
          ),
          verifiedAt: 950,
        );
        final harness = _Harness(
          state: _activeState(head: localHead),
          safeHeadResult: WalletMetadataSafeHeadCompatible(remote),
          contributors: [
            _FakeContributor(recordType: 'labels.bip329', records: const []),
          ],
        );

        final outcome = _requireOk(await harness.execute());

        expect(outcome.status, WalletMetadataPublishStatus.verified);
        expect(harness.snapshot.lastRecords, isEmpty);
        expect(harness.snapshot.lastSections.single.recordCount, 0);
        expect(harness.snapshot.lastRevision, 6);
        expect(harness.relay.lastSnapshot?.chunks, isEmpty);
        expect(harness.state.state.dirty, isFalse);
      },
    );

    test('relay repository failure remains retryable', () async {
      final harness = _Harness(
        relayFailure: const WalletMetadataBackupRelayFailure(),
      );

      final failure = _requireFailure(await harness.execute());

      expect(failure, isA<WalletMetadataBackupRelayFailure>());
      expect(harness.state.state.lastAcceptedAt, isNull);
      expect(harness.state.state.dirty, isTrue);
    });
  });
}

final class _Harness {
  late final _FakeStateRepository state;
  late final _FakeSafeHeadRepository safeHead;
  late final _CapturingSnapshotRepository snapshot;
  late final _FakeRelayRepository relay;
  late final PublishWalletMetadataBackupUsecase usecase;

  _Harness({
    WalletMetadataBackupState? state,
    WalletMetadataSafeHeadResult safeHeadResult =
        const WalletMetadataSafeHeadNoSnapshot(),
    List<_FakeContributor>? contributors,
    WalletMetadataRelayReplicaStatus relayStatus =
        WalletMetadataRelayReplicaStatus.verified,
    WalletMetadataBackupFailure? relayFailure,
    int now = _now,
  }) {
    this.state = _FakeStateRepository(state ?? _activeState());
    safeHead = _FakeSafeHeadRepository(Ok(safeHeadResult));
    snapshot = _CapturingSnapshotRepository();
    relay = _FakeRelayRepository(status: relayStatus, failure: relayFailure);
    usecase = PublishWalletMetadataBackupUsecase(
      stateRepository: this.state,
      safeHeadRepository: safeHead,
      compositionRepository:
          const WalletMetadataSnapshotCompositionRepositoryImpl(),
      snapshotRepository: snapshot,
      relayRepository: relay,
      contributors:
          contributors ??
          [
            _FakeContributor(
              recordType: 'labels.bip329',
              records: [_record('labels.bip329', 1, 'label-1', 'local label')],
            ),
          ],
      relayPolicy: const NostrRelayPolicyFacade(
        relayUrlsOverride: 'wss://relay.example',
      ),
      clock: _FixedClock(now),
    );
  }

  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  execute() {
    return usecase.execute(
      xprvBase58: _masterXprv,
      parentFingerprint: _parentFingerprint,
    );
  }
}

final class _FakeStateRepository
    implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state;
  WalletMetadataBackupState? stateBeforeNextUpdate;
  int fetchCount = 0;
  int updateCount = 0;

  _FakeStateRepository(this.state);

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  fetch() async {
    fetchCount++;
    return Ok(state);
  }

  @override
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>> update(
    WalletMetadataBackupStateUpdate update,
  ) async {
    updateCount++;
    final replacement = stateBeforeNextUpdate;
    if (replacement != null) {
      state = replacement;
      stateBeforeNextUpdate = null;
    }
    state = update(state);
    return Ok(state);
  }
}

final class _FakeSafeHeadRepository
    implements WalletMetadataSafeHeadRepository {
  final Result<WalletMetadataSafeHeadResult, WalletMetadataBackupFailure>
  result;
  int fetchCount = 0;

  _FakeSafeHeadRepository(this.result);

  @override
  Future<Result<WalletMetadataSafeHeadResult, WalletMetadataBackupFailure>>
  fetchForPublication({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
    fetchCount++;
    return result;
  }
}

final class _FakeContributor implements WalletMetadataContributor {
  @override
  final String recordType;
  @override
  final Set<int> supportedVersions;
  final List<WalletMetadataRecord> records;
  final WalletMetadataBackupFailure? failure;
  final void Function()? onExport;
  int exportCount = 0;

  _FakeContributor({
    required this.recordType,
    this.supportedVersions = const {1},
    this.records = const [],
    this.failure,
    this.onExport,
  });

  @override
  WalletMetadataRecordValidation validateRecord(WalletMetadataRecord record) {
    return WalletMetadataRecordValid(
      WalletMetadataImportIntent(contributorType: recordType, record: record),
    );
  }

  @override
  Future<Result<List<WalletMetadataRecord>, WalletMetadataBackupFailure>>
  exportRecords() async {
    exportCount++;
    onExport?.call();
    final exportFailure = failure;
    return exportFailure == null ? Ok(records) : Err(exportFailure);
  }
}

final class _CapturingSnapshotRepository
    implements WalletMetadataSnapshotRepository {
  final WalletMetadataSnapshotRepositoryImpl _delegate;
  int buildCount = 0;
  int? lastRevision;
  int? lastCreatedAt;
  List<WalletMetadataRecord> lastRecords = const [];
  List<WalletMetadataSection> lastSections = const [];

  _CapturingSnapshotRepository() : _delegate = _snapshotRepository();

  @override
  Result<WalletMetadataEncryptedSnapshot, WalletMetadataBackupFailure> build({
    required String xprvBase58,
    required String parentFingerprint,
    required int revision,
    required int createdAt,
    required List<WalletMetadataRecord> records,
    required List<WalletMetadataSection> sections,
  }) {
    buildCount++;
    lastRevision = revision;
    lastCreatedAt = createdAt;
    lastRecords = List.unmodifiable(records);
    lastSections = List.unmodifiable(sections);
    return _delegate.build(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
      revision: revision,
      createdAt: createdAt,
      records: records,
      sections: sections,
    );
  }
}

final class _FakeRelayRepository implements WalletMetadataRelayRepository {
  final WalletMetadataRelayReplicaStatus status;
  final WalletMetadataBackupFailure? failure;
  int publishCount = 0;
  WalletMetadataEncryptedSnapshot? lastSnapshot;
  void Function()? onPublish;

  _FakeRelayRepository({required this.status, required this.failure});

  @override
  Future<Result<WalletMetadataSnapshotPublication, WalletMetadataBackupFailure>>
  publishAndVerify({
    required WalletMetadataEncryptedSnapshot snapshot,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
    publishCount++;
    lastSnapshot = snapshot;
    onPublish?.call();
    final relayFailure = failure;
    if (relayFailure != null) return Err(relayFailure);
    return Ok(
      WalletMetadataSnapshotPublication(
        relayOutcomes: [
          WalletMetadataRelayReplicaOutcome(
            relayUrl: relayUrls.first,
            status: status,
            acceptedChunkCount:
                status == WalletMetadataRelayReplicaStatus.chunksNotAccepted
                ? 0
                : snapshot.chunks.length,
            expectedChunkCount: snapshot.chunks.length,
            contactedRelay: true,
          ),
        ],
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

WalletMetadataSnapshotRepositoryImpl _snapshotRepository() {
  var randomCounter = 0;
  return WalletMetadataSnapshotRepositoryImpl(
    nostrIdentity: _nostrIdentity,
    randomHex: (byteLength) {
      randomCounter++;
      return randomCounter
          .toRadixString(16)
          .padLeft(byteLength * 2, '0')
          .substring(0, byteLength * 2);
    },
  );
}

WalletMetadataBackupState _activeState({
  WalletMetadataBackupVerifiedHead? head,
}) {
  var state = WalletMetadataBackupState.initial
      .withEnabled(true)
      .acknowledgeRelayDisclosure();
  if (head != null) {
    state = state
        .recordVerifiedHead(head: head, expectedDirtyRevision: 1)
        .markDirty();
  }
  return state;
}

WalletMetadataRecord _record(
  String type,
  int version,
  String id,
  String value,
) {
  return WalletMetadataRecord(
    type: type,
    version: version,
    scope: const {'kind': 'global'},
    recordId: id,
    payload: {'value': value},
  );
}

WalletMetadataRemoteHead _remoteHead({
  required List<WalletMetadataRecord> records,
  required int revision,
  required int createdAt,
  int? highestObservedCreatedAt,
  Map<String, List<int>>? sectionVersions,
}) {
  const codec = WalletMetadataSnapshotCodec();
  final versions =
      sectionVersions ??
      {
        for (final type in records.map((record) => record.type).toSet())
          type: records
              .where((record) => record.type == type)
              .map((record) => record.version)
              .toSet()
              .toList(growable: false),
      };
  final sections = versions.entries
      .map((entry) {
        final sectionRecords = records
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
    rootEventCreatedAt: createdAt,
    highestObservedRootCreatedAt: highestObservedCreatedAt ?? createdAt,
    canonicalContentHash: codec.contentHash(
      records: records,
      sections: sections,
    ),
    root: WalletMetadataSnapshotRoot(
      parentFingerprint: _parentFingerprint,
      snapshotId: '6' * 32,
      revision: revision,
      createdAt: createdAt,
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
}

WalletMetadataBackupUnsupportedEnvelope _unsupportedEnvelope() {
  return WalletMetadataBackupUnsupportedEnvelope(
    rootEventId: '2' * 64,
    envelopeVersion: 2,
    eventCreatedAt: 900,
    observedAt: _now,
  );
}

WalletMetadataPublishOutcome _requireOk(
  Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected Ok, got ${failure.runtimeType}',
    ),
  };
}

WalletMetadataBackupFailure _requireFailure(
  Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => throw TestFailure(
      'expected failure, got ${value.status}',
    ),
    Err(:final failure) => failure,
  };
}

const _nostrIdentity = NostrIdentityFacade(
  deriveHandle: DeriveNostrIdentityHandleUsecase(
    registry: Bip85RegistryFacade(),
  ),
);
const _masterXprv =
    'xprv9s21ZrQH143K2LBWUUQRFXhucrQqBpKdRRxNVq2zBqsx8HVqFk2uYo8kmbaLLHRdqtQpUm98uKfu3vca1LqdGhUtyoFnCNkfmXRyPXLjbKb';
const _parentFingerprint = '627ef3a6';
const _now = 1000;
