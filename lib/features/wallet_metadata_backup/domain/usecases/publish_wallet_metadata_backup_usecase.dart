import 'dart:math';

import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_encrypted_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_inventory.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_relay_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_safe_head_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_composition_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_snapshot_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:meta/meta.dart';

final class PublishWalletMetadataBackupUsecase {
  final WalletMetadataBackupStateRepository _stateRepository;
  final WalletMetadataSafeHeadRepository _safeHeadRepository;
  final WalletMetadataSnapshotCompositionRepository _compositionRepository;
  final WalletMetadataSnapshotRepository _snapshotRepository;
  final WalletMetadataRelayRepository _relayRepository;
  final List<WalletMetadataContributor> _contributors;
  final NostrRelayPolicyFacade _relayPolicy;
  final Clock _clock;

  PublishWalletMetadataBackupUsecase({
    required this._stateRepository,
    required this._safeHeadRepository,
    required this._compositionRepository,
    required this._snapshotRepository,
    required this._relayRepository,
    required List<WalletMetadataContributor> contributors,
    this._relayPolicy = const NostrRelayPolicyFacade(),
    this._clock = const SystemClock(),
  }) : _contributors = List.unmodifiable(contributors) {
    if (_contributors.isEmpty) {
      throw ArgumentError.value(
        contributors,
        'contributors',
        'must not be empty',
      );
    }
  }

  @useResult
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  execute({
    required String xprvBase58,
    required String parentFingerprint,
  }) async {
    final initialResult = await _stateRepository.fetch();
    final WalletMetadataBackupState initial;
    switch (initialResult) {
      case Ok(:final value):
        initial = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (initial.unsupportedNewerEnvelope != null) {
      return const Err(WalletMetadataBackupUpdateRequiredFailure());
    }
    if (!initial.canAttemptPublication) {
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.notReady,
        ),
      );
    }

    final now = _clock.nowSecs();
    if (now < 0 || now > WalletMetadataBackupLimits.maxSignedInt64) {
      return const Err(WalletMetadataBackupClockFailure());
    }
    final attemptedResult = await _stateRepository.update(
      (state) => state.canAttemptPublication
          ? state.recordPublicationAttempted(now)
          : state,
    );
    final WalletMetadataBackupState publicationState;
    switch (attemptedResult) {
      case Ok(:final value):
        publicationState = value;
      case Err(:final failure):
        return Err(failure);
    }
    if (publicationState.unsupportedNewerEnvelope != null) {
      return const Err(WalletMetadataBackupUpdateRequiredFailure());
    }
    if (!publicationState.canAttemptPublication) {
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.notReady,
        ),
      );
    }
    final dirtyRevision = publicationState.dirtyRevision;

    final relayUrls = _relayPolicy
        .getPolicy()
        .defaultRelays
        .map((relay) => WalletMetadataRelayUrl(relay.url))
        .toSet()
        .toList(growable: false);
    if (relayUrls.isEmpty) {
      return const Err(WalletMetadataBackupRelayFailure());
    }
    final safeHeadResult = await _safeHeadRepository.fetchForPublication(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
      relayUrls: relayUrls,
    );
    final WalletMetadataSafeHeadResult safeHead;
    switch (safeHeadResult) {
      case Ok(:final value):
        safeHead = value;
      case Err(:final failure):
        return Err(failure);
    }
    final WalletMetadataRemoteHead? remoteHead;
    switch (safeHead) {
      case WalletMetadataSafeHeadNoSnapshot():
        remoteHead = null;
      case WalletMetadataSafeHeadCompatible(:final head):
        remoteHead = head;
      case WalletMetadataSafeHeadUnsupported(:final unsupported):
        return _recordUnsupportedAndFail(unsupported);
      case WalletMetadataSafeHeadIncomplete():
        return const Err(WalletMetadataBackupRemoteHeadFailure());
      case WalletMetadataSafeHeadUnavailable():
        return const Err(WalletMetadataBackupRelayFailure());
    }

    final inventories = <WalletMetadataContributorInventory>[];
    for (final contributor in _contributors) {
      final exportResult = await contributor.exportRecords();
      switch (exportResult) {
        case Ok(:final value):
          inventories.add(
            WalletMetadataContributorInventory(
              recordType: contributor.recordType,
              supportedVersions: contributor.supportedVersions,
              records: value,
            ),
          );
        case Err(:final failure):
          return Err(failure);
      }
    }
    final inventoryResult = _compositionRepository.compose(
      contributors: inventories,
      remoteHead: remoteHead,
    );
    final WalletMetadataSnapshotInventory inventory;
    switch (inventoryResult) {
      case Ok(:final value):
        inventory = value;
      case Err(:final failure):
        return Err(failure);
    }

    if (inventory.isEmpty &&
        remoteHead == null &&
        publicationState.verifiedHead == null) {
      final cleanResult = await _stateRepository.update(
        (state) => state.recordNoPublicationNeeded(
          expectedDirtyRevision: dirtyRevision,
        ),
      );
      if (cleanResult case Err(:final failure)) return Err(failure);
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.initialEmpty,
        ),
      );
    }

    final localVerifiedRevision =
        publicationState.verifiedHead?.snapshotRevision ?? 0;
    final compatibleRemoteHead = remoteHead;
    if (compatibleRemoteHead != null &&
        compatibleRemoteHead.root.recordsHash == inventory.recordsHash &&
        _sameSections(compatibleRemoteHead.root.sections, inventory.sections) &&
        compatibleRemoteHead.root.revision >= localVerifiedRevision) {
      final verifiedResult = await _stateRepository.update(
        (state) => state.recordVerifiedHead(
          head: WalletMetadataBackupVerifiedHead(
            rootEventId: compatibleRemoteHead.rootEventId,
            snapshotRevision: compatibleRemoteHead.root.revision,
            canonicalContentHash: inventory.canonicalContentHash,
            verifiedAt: now,
          ),
          expectedDirtyRevision: dirtyRevision,
        ),
      );
      if (verifiedResult case Err(:final failure)) return Err(failure);
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.unchanged,
        ),
      );
    }

    final baseRevision = max(
      localVerifiedRevision,
      remoteHead?.root.revision ?? 0,
    );
    if (baseRevision >= WalletMetadataBackupLimits.maxSignedInt64) {
      return const Err(WalletMetadataBackupClockFailure());
    }
    final highestRootCreatedAt = remoteHead?.highestObservedRootCreatedAt ?? -1;
    if (highestRootCreatedAt >= WalletMetadataBackupLimits.maxSignedInt64) {
      return const Err(WalletMetadataBackupClockFailure());
    }
    final eventCreatedAt = max(now, highestRootCreatedAt + 1);
    final snapshotResult = _snapshotRepository.build(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
      revision: baseRevision + 1,
      createdAt: eventCreatedAt,
      records: inventory.records,
      sections: inventory.sections,
    );
    final WalletMetadataEncryptedSnapshot snapshot;
    switch (snapshotResult) {
      case Ok(:final value):
        snapshot = value;
      case Err(:final failure):
        return Err(failure);
    }
    final publicationResult = await _relayRepository.publishAndVerify(
      snapshot: snapshot,
      relayUrls: relayUrls,
    );
    final WalletMetadataSnapshotPublication publication;
    switch (publicationResult) {
      case Ok(:final value):
        publication = value;
      case Err(:final failure):
        return Err(failure);
    }

    if (publication.acceptedReplicaCount > 0) {
      final acceptedResult = await _stateRepository.update(
        (state) => state.recordPublicationAccepted(now),
      );
      if (acceptedResult case Err(:final failure)) return Err(failure);
    }
    if (publication.verifiedReplicaCount > 0) {
      final verifiedResult = await _stateRepository.update(
        (state) => state.recordVerifiedHead(
          head: WalletMetadataBackupVerifiedHead(
            rootEventId: snapshot.rootEvent.id,
            snapshotRevision: snapshot.plaintextRoot.revision,
            canonicalContentHash: inventory.canonicalContentHash,
            verifiedAt: now,
          ),
          expectedDirtyRevision: dirtyRevision,
        ),
      );
      if (verifiedResult case Err(:final failure)) return Err(failure);
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.verified,
          acceptedReplicaCount: publication.acceptedReplicaCount,
          verifiedReplicaCount: publication.verifiedReplicaCount,
          rootEventId: snapshot.rootEvent.id,
        ),
      );
    }
    if (publication.acceptedReplicaCount > 0) {
      return Ok(
        WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.acceptedUnverified,
          acceptedReplicaCount: publication.acceptedReplicaCount,
          rootEventId: snapshot.rootEvent.id,
        ),
      );
    }
    return Ok(
      WalletMetadataPublishOutcome(
        status: WalletMetadataPublishStatus.notAccepted,
        rootEventId: snapshot.rootEvent.id,
      ),
    );
  }

  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  _recordUnsupportedAndFail(
    WalletMetadataBackupUnsupportedEnvelope unsupported,
  ) async {
    final updateResult = await _stateRepository.update(
      (state) => state.recordUnsupportedNewerEnvelope(unsupported),
    );
    if (updateResult case Err(:final failure)) return Err(failure);
    return const Err(WalletMetadataBackupUpdateRequiredFailure());
  }
}

bool _sameSections(
  List<WalletMetadataSection> left,
  List<WalletMetadataSection> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    final leftSection = left[index];
    final rightSection = right[index];
    if (leftSection.type != rightSection.type ||
        leftSection.recordCount != rightSection.recordCount ||
        leftSection.recordsHash != rightSection.recordsHash ||
        !_sameVersions(leftSection.versions, rightSection.versions)) {
      return false;
    }
  }
  return true;
}

bool _sameVersions(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
