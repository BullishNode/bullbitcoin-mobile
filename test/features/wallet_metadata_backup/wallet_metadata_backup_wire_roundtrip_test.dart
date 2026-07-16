import 'package:bb_mobile/core/nostr/nostr_relay_transport.dart';
import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/bip85_registry/public/bip85_registry_facade.dart';
import 'package:bb_mobile/features/nostr_identity/domain/derive_nostr_identity_handle_usecase.dart';
import 'package:bb_mobile/features/nostr_identity/public/nostr_identity_facade.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_safe_head_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_composition_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/wallet_metadata_snapshot_repository_impl.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/data/websocket_wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_root.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/apply_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/fetch_wallet_metadata_recovery_plan_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/publish_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_root_port.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_json.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/fake_nostr_relay.dart';

void main() {
  test(
    'publish, read back, recover, validate, and apply through a fake relay',
    () async {
      final relay = FakeNostrRelay();
      final transport = NostrRelayTransport(connect: relay.connect);
      final graphRepository = WebSocketWalletMetadataGraphRepository(
        nostrIdentity: _nostrIdentity,
        transport: transport,
        timeout: const Duration(seconds: 1),
      );
      final relayPolicy = const NostrRelayPolicyFacade(
        relayUrlsOverride: 'wss://metadata.test',
      );
      final senderState = _MemoryStateRepository(_activeState());
      final senderContributors = _sourceContributors();
      var randomCounter = 0;
      final publisher = PublishWalletMetadataBackupUsecase(
        stateRepository: senderState,
        safeHeadRepository: WalletMetadataSafeHeadRepositoryImpl(
          graphRepository: graphRepository,
          clock: const _FixedClock(_publishTime),
        ),
        compositionRepository:
            const WalletMetadataSnapshotCompositionRepositoryImpl(),
        snapshotRepository: WalletMetadataSnapshotRepositoryImpl(
          nostrIdentity: _nostrIdentity,
          randomHex: (byteLength) {
            randomCounter++;
            return randomCounter
                .toRadixString(16)
                .padLeft(byteLength * 2, '0')
                .substring(0, byteLength * 2);
          },
        ),
        relayRepository: WebSocketWalletMetadataRelayRepository(
          transport: transport,
          timeout: const Duration(seconds: 1),
        ),
        contributors: senderContributors,
        relayPolicy: relayPolicy,
        clock: const _FixedClock(_publishTime),
      );

      final publication = _requirePublishOk(
        await publisher.execute(
          xprvBase58: _masterXprv,
          parentFingerprint: _parentFingerprint,
        ),
      );

      expect(publication.status, WalletMetadataPublishStatus.verified);
      expect(publication.verifiedReplicaCount, 1);
      expect(senderState.state.dirty, isFalse);
      expect(senderState.state.verifiedHead?.snapshotRevision, 1);
      expect(relay.storedEventCount, greaterThan(2));
      expect(
        relay.capturedEventFrames.every(
          (frame) =>
              !frame.contains('first private label') &&
              !frame.contains('second private label') &&
              !frame.contains('labels.bip329'),
        ),
        isTrue,
      );
      expect(
        _nostrIdentity.deriveWalletMetadataPublicKeyFromXprv(_masterXprv),
        isNot(
          _nostrIdentity.deriveWalletManifestPublicKeyFromXprv(_masterXprv),
        ),
      );

      final publishedFrameCount = relay.capturedEventFrames.length;
      final receiverState = _MemoryStateRepository(
        WalletMetadataBackupState.initial.acknowledgeRelayDisclosure(),
      );
      final receiverContributors = _emptyContributors();
      final recovery = _requireRecoveryOk(
        await FetchWalletMetadataRecoveryPlanUsecase(
          stateRepository: receiverState,
          graphRepository: graphRepository,
          contributors: receiverContributors,
          relayPolicy: relayPolicy,
          clock: const _FixedClock(_recoveryTime),
        ).execute(
          xprvBase58: _masterXprv,
          parentFingerprint: _parentFingerprint,
        ),
      );

      expect(recovery.status, WalletMetadataRecoveryStatus.latestSnapshot);
      expect(recovery.plan, isNotNull);
      expect(recovery.plan!.plannedRecordCount, 4);
      expect(receiverState.state.enabled, isFalse);
      expect(receiverState.updateCount, 0);

      final guard = WalletMetadataPublicationGuard();
      final applied = _requireApplyOk(
        await ApplyWalletMetadataRecoveryPlanUsecase(
          const _FixedRootPort(),
          stateRepository: receiverState,
          contributors: receiverContributors,
          publicationGuard: guard,
          clock: const _FixedClock(_recoveryTime),
        ).execute(
          plan: recovery.plan!,
          createdWalletRefs: const {'wallet-main'},
        ),
      );

      expect(applied.status, WalletMetadataRecoveryApplyStatus.latestComplete);
      expect(applied.restoredCount, 4);
      expect(receiverState.state.enabled, isFalse);
      expect(receiverState.state.dirty, isFalse);
      expect(receiverState.state.recoveryBlock, isNull);
      expect(
        receiverState.state.verifiedHead?.rootEventId,
        publication.rootEventId,
      );
      expect(guard.isPublicationSuppressed, isFalse);
      expect(relay.capturedEventFrames, hasLength(publishedFrameCount));
      expect(
        receiverContributors
            .expand((contributor) => contributor.records)
            .map(_recordSignature)
            .toSet(),
        senderContributors
            .expand((contributor) => contributor.records)
            .map(_recordSignature)
            .toSet(),
      );
    },
  );
}

String _recordSignature(WalletMetadataRecord record) =>
    '${record.identity}|${walletMetadataCanonicalJsonEncode(record.payload)}';

List<_MemoryContributor> _sourceContributors() {
  return [
    _MemoryContributor('labels.bip329', [
      _record(
        type: 'labels.bip329',
        id: 'tx-label-1',
        payload: {
          'type': 'tx',
          'ref': '1' * 64,
          'label': 'first private label ${'a' * 60000}',
        },
      ),
      _record(
        type: 'labels.bip329',
        id: 'tx-label-2',
        payload: {
          'type': 'tx',
          'ref': '2' * 64,
          'label': 'second private label ${'b' * 60000}',
        },
      ),
    ]),
    _MemoryContributor('wallet.utxo_freeze', [
      _record(
        type: 'wallet.utxo_freeze',
        id: 'wallet-main:outpoint-1',
        payload: {
          'walletRef': 'wallet-main',
          'outpoint': '${'3' * 64}:0',
          'isFrozen': true,
        },
      ),
    ]),
    _MemoryContributor('wallet.preferences', [
      _record(
        type: 'wallet.preferences',
        id: 'wallet-main',
        payload: const {
          'walletRef': 'wallet-main',
          'label': 'Daily wallet',
          'hideOnHome': false,
          'autoSweepEnabled': true,
        },
      ),
    ]),
  ];
}

List<_MemoryContributor> _emptyContributors() => [
  _MemoryContributor('labels.bip329'),
  _MemoryContributor('wallet.utxo_freeze'),
  _MemoryContributor('wallet.preferences'),
];

WalletMetadataRecord _record({
  required String type,
  required String id,
  required Map<String, Object?> payload,
}) {
  return WalletMetadataRecord(
    type: type,
    version: 1,
    scope: const {'kind': 'global'},
    recordId: id,
    payload: payload,
  );
}

final class _MemoryContributor implements WalletMetadataRestoringContributor {
  @override
  final String recordType;
  final List<WalletMetadataRecord> records;

  _MemoryContributor(
    this.recordType, [
    Iterable<WalletMetadataRecord> initialRecords = const [],
  ]) : records = List.of(initialRecords);

  @override
  Set<int> get supportedVersions => const {1};

  @override
  Future<Result<List<WalletMetadataRecord>, WalletMetadataBackupFailure>>
  exportRecords() async => Ok(List.unmodifiable(records));

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
    final existing = records.map((record) => record.identity).toSet();
    var restored = 0;
    var alreadyPresent = 0;
    for (final intent in intents) {
      if (existing.add(intent.recordIdentity)) {
        records.add(intent.record);
        restored++;
      } else {
        alreadyPresent++;
      }
    }
    return Ok(
      WalletMetadataContributorApplySummary(
        contributorType: recordType,
        intendedCount: intents.length,
        restoredCount: restored,
        alreadyPresentCount: alreadyPresent,
        preservedLocalConflictCount: 0,
        deferredMissingWalletCount: 0,
        localProjectionMatchesSnapshot: true,
      ),
    );
  }
}

final class _MemoryStateRepository
    implements WalletMetadataBackupStateRepository {
  WalletMetadataBackupState state;
  int updateCount = 0;

  _MemoryStateRepository(this.state);

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

final class _FixedRootPort implements WalletMetadataBackupRootPort {
  const _FixedRootPort();

  @override
  Future<Result<WalletMetadataBackupRoot, WalletMetadataBackupFailure>>
  deriveLocalRoot() async {
    return Ok(
      WalletMetadataBackupRoot(
        xprvBase58: _masterXprv,
        parentFingerprint: _parentFingerprint,
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

WalletMetadataBackupState _activeState() => WalletMetadataBackupState.initial
    .withEnabled(true)
    .acknowledgeRelayDisclosure();

WalletMetadataPublishOutcome _requirePublishOk(
  Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected publication, got ${failure.runtimeType}',
    ),
  };
}

WalletMetadataRecoveryResult _requireRecoveryOk(
  Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected recovery plan, got ${failure.runtimeType}',
    ),
  };
}

WalletMetadataRecoveryApplyResult _requireApplyOk(
  Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure> result,
) {
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw TestFailure(
      'expected recovery apply, got ${failure.runtimeType}',
    ),
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
const _publishTime = 1700000000;
const _recoveryTime = 1700000100;
