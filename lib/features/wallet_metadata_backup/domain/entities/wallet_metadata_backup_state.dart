import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';

final RegExp _eventIdPattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _contentHashPattern = RegExp(r'^[0-9a-f]{64}$');

final class WalletMetadataBackupVerifiedHead {
  final String rootEventId;
  final int snapshotRevision;
  final String canonicalContentHash;
  final int verifiedAt;

  WalletMetadataBackupVerifiedHead({
    required this.rootEventId,
    required this.snapshotRevision,
    required this.canonicalContentHash,
    required this.verifiedAt,
  }) {
    _validateEventId(rootEventId, 'rootEventId');
    _validateNonNegativeInt64(snapshotRevision, 'snapshotRevision');
    if (!_contentHashPattern.hasMatch(canonicalContentHash)) {
      throw ArgumentError.value(
        canonicalContentHash,
        'canonicalContentHash',
        'must be lowercase 32-byte hex',
      );
    }
    _validateNonNegativeInt64(verifiedAt, 'verifiedAt');
  }
}

final class WalletMetadataBackupUnsupportedEnvelope {
  final String rootEventId;
  final int envelopeVersion;
  final int eventCreatedAt;
  final int observedAt;

  WalletMetadataBackupUnsupportedEnvelope({
    required this.rootEventId,
    required this.envelopeVersion,
    required this.eventCreatedAt,
    required this.observedAt,
  }) {
    _validateEventId(rootEventId, 'rootEventId');
    if (envelopeVersion <= walletMetadataEnvelopeVersion ||
        envelopeVersion > WalletMetadataBackupLimits.maxSignedInt64) {
      throw ArgumentError.value(
        envelopeVersion,
        'envelopeVersion',
        'must be newer than the supported envelope version',
      );
    }
    _validateNonNegativeInt64(eventCreatedAt, 'eventCreatedAt');
    _validateNonNegativeInt64(observedAt, 'observedAt');
  }
}

enum WalletMetadataRecoveryBlockReason {
  applyInProgress,
  olderSnapshot,
  incompleteApply,
}

final class WalletMetadataBackupRecoveryBlock {
  final WalletMetadataRecoveryBlockReason reason;
  final String rootEventId;
  final int snapshotRevision;
  final int eventCreatedAt;
  final int observedAt;

  WalletMetadataBackupRecoveryBlock({
    required this.reason,
    required this.rootEventId,
    required this.snapshotRevision,
    required this.eventCreatedAt,
    required this.observedAt,
  }) {
    _validateEventId(rootEventId, 'rootEventId');
    _validateNonNegativeInt64(snapshotRevision, 'snapshotRevision');
    _validateNonNegativeInt64(eventCreatedAt, 'eventCreatedAt');
    _validateNonNegativeInt64(observedAt, 'observedAt');
  }

  WalletMetadataBackupRecoveryBlock withReason(
    WalletMetadataRecoveryBlockReason value,
  ) {
    return WalletMetadataBackupRecoveryBlock(
      reason: value,
      rootEventId: rootEventId,
      snapshotRevision: snapshotRevision,
      eventCreatedAt: eventCreatedAt,
      observedAt: observedAt,
    );
  }
}

final class WalletMetadataBackupState {
  static const initial = WalletMetadataBackupState._(
    enabled: false,
    relayDisclosureAcknowledged: false,
    dirty: false,
    dirtyRevision: 0,
    lastAttemptedAt: null,
    lastAcceptedAt: null,
    verifiedHead: null,
    unsupportedNewerEnvelope: null,
    recoveryBlock: null,
  );

  final bool enabled;
  final bool relayDisclosureAcknowledged;
  final bool dirty;
  final int dirtyRevision;
  final int? lastAttemptedAt;
  final int? lastAcceptedAt;
  final WalletMetadataBackupVerifiedHead? verifiedHead;
  final WalletMetadataBackupUnsupportedEnvelope? unsupportedNewerEnvelope;
  final WalletMetadataBackupRecoveryBlock? recoveryBlock;

  factory WalletMetadataBackupState({
    required bool enabled,
    required bool relayDisclosureAcknowledged,
    required bool dirty,
    required int dirtyRevision,
    required int? lastAttemptedAt,
    required int? lastAcceptedAt,
    required WalletMetadataBackupVerifiedHead? verifiedHead,
    required WalletMetadataBackupUnsupportedEnvelope? unsupportedNewerEnvelope,
    required WalletMetadataBackupRecoveryBlock? recoveryBlock,
  }) {
    if (lastAttemptedAt != null) {
      _validateNonNegativeInt64(lastAttemptedAt, 'lastAttemptedAt');
    }
    if (lastAcceptedAt != null) {
      _validateNonNegativeInt64(lastAcceptedAt, 'lastAcceptedAt');
    }
    _validateNonNegativeInt64(dirtyRevision, 'dirtyRevision');
    return WalletMetadataBackupState._(
      enabled: enabled,
      relayDisclosureAcknowledged: relayDisclosureAcknowledged,
      dirty: dirty,
      dirtyRevision: dirtyRevision,
      lastAttemptedAt: lastAttemptedAt,
      lastAcceptedAt: lastAcceptedAt,
      verifiedHead: verifiedHead,
      unsupportedNewerEnvelope: unsupportedNewerEnvelope,
      recoveryBlock: recoveryBlock,
    );
  }

  const WalletMetadataBackupState._({
    required this.enabled,
    required this.relayDisclosureAcknowledged,
    required this.dirty,
    required this.dirtyRevision,
    required this.lastAttemptedAt,
    required this.lastAcceptedAt,
    required this.verifiedHead,
    required this.unsupportedNewerEnvelope,
    required this.recoveryBlock,
  });

  bool get canContactRelays => enabled && relayDisclosureAcknowledged;

  bool get canAttemptPublication =>
      canContactRelays &&
      dirty &&
      unsupportedNewerEnvelope == null &&
      recoveryBlock == null;

  WalletMetadataBackupState withEnabled(bool value) {
    if (value == enabled) return this;
    if (!value) return _copy(enabled: false);
    return _copy(
      enabled: true,
      dirty: true,
      dirtyRevision: _nextDirtyRevision(),
    );
  }

  WalletMetadataBackupState acknowledgeRelayDisclosure() {
    if (relayDisclosureAcknowledged) return this;
    return _copy(relayDisclosureAcknowledged: true);
  }

  WalletMetadataBackupState markDirty() {
    return _copy(dirty: true, dirtyRevision: _nextDirtyRevision());
  }

  WalletMetadataBackupState recordPublicationAttempted(int attemptedAt) {
    _validateNonNegativeInt64(attemptedAt, 'attemptedAt');
    return _copy(lastAttemptedAt: _latest(lastAttemptedAt, attemptedAt));
  }

  WalletMetadataBackupState recordPublicationAccepted(int acceptedAt) {
    _validateNonNegativeInt64(acceptedAt, 'acceptedAt');
    return _copy(lastAcceptedAt: _latest(lastAcceptedAt, acceptedAt));
  }

  WalletMetadataBackupState recordVerifiedHead({
    required WalletMetadataBackupVerifiedHead head,
    required int expectedDirtyRevision,
  }) {
    _validateNonNegativeInt64(expectedDirtyRevision, 'expectedDirtyRevision');
    final currentHead = verifiedHead;
    if (currentHead != null) {
      if (head.snapshotRevision < currentHead.snapshotRevision ||
          (head.snapshotRevision == currentHead.snapshotRevision &&
              head.canonicalContentHash != currentHead.canonicalContentHash)) {
        return this;
      }
      if (head.snapshotRevision == currentHead.snapshotRevision) {
        final latestVerifiedAt = _latest(
          currentHead.verifiedAt,
          head.verifiedAt,
        );
        head = WalletMetadataBackupVerifiedHead(
          rootEventId: currentHead.rootEventId,
          snapshotRevision: currentHead.snapshotRevision,
          canonicalContentHash: currentHead.canonicalContentHash,
          verifiedAt: latestVerifiedAt,
        );
      }
    }
    return _copy(
      verifiedHead: head,
      dirty: dirtyRevision == expectedDirtyRevision ? false : dirty,
    );
  }

  WalletMetadataBackupState recordNoPublicationNeeded({
    required int expectedDirtyRevision,
  }) {
    _validateNonNegativeInt64(expectedDirtyRevision, 'expectedDirtyRevision');
    return _copy(dirty: dirtyRevision == expectedDirtyRevision ? false : dirty);
  }

  WalletMetadataBackupState recordUnsupportedNewerEnvelope(
    WalletMetadataBackupUnsupportedEnvelope unsupported,
  ) {
    return _copy(unsupportedNewerEnvelope: unsupported);
  }

  WalletMetadataBackupState recordRecoveryApplyStarted(
    WalletMetadataBackupRecoveryBlock block,
  ) {
    if (block.reason != WalletMetadataRecoveryBlockReason.applyInProgress) {
      throw ArgumentError.value(block.reason, 'block.reason');
    }
    return _copy(
      dirty: true,
      dirtyRevision: _nextDirtyRevision(),
      recoveryBlock: block,
    );
  }

  WalletMetadataBackupState recordRecoveryApplyBlocked(
    WalletMetadataBackupRecoveryBlock block,
  ) {
    if (block.reason == WalletMetadataRecoveryBlockReason.applyInProgress) {
      throw ArgumentError.value(block.reason, 'block.reason');
    }
    return _copy(dirty: true, recoveryBlock: block);
  }

  WalletMetadataBackupState recordRecoveryAppliedClean({
    required WalletMetadataBackupVerifiedHead head,
  }) {
    final currentHead = verifiedHead;
    if (currentHead != null &&
        (head.snapshotRevision < currentHead.snapshotRevision ||
            (head.snapshotRevision == currentHead.snapshotRevision &&
                head.canonicalContentHash !=
                    currentHead.canonicalContentHash))) {
      final currentBlock = recoveryBlock;
      return currentBlock == null
          ? this
          : _copy(
              dirty: true,
              recoveryBlock: currentBlock.withReason(
                WalletMetadataRecoveryBlockReason.incompleteApply,
              ),
            );
    }
    return _copy(
      verifiedHead: head,
      dirty: false,
      clearUnsupportedNewerEnvelope: true,
      clearRecoveryBlock: true,
    );
  }

  WalletMetadataBackupState _copy({
    bool? enabled,
    bool? relayDisclosureAcknowledged,
    bool? dirty,
    int? dirtyRevision,
    int? lastAttemptedAt,
    int? lastAcceptedAt,
    WalletMetadataBackupVerifiedHead? verifiedHead,
    WalletMetadataBackupUnsupportedEnvelope? unsupportedNewerEnvelope,
    WalletMetadataBackupRecoveryBlock? recoveryBlock,
    bool clearUnsupportedNewerEnvelope = false,
    bool clearRecoveryBlock = false,
  }) {
    return WalletMetadataBackupState._(
      enabled: enabled ?? this.enabled,
      relayDisclosureAcknowledged:
          relayDisclosureAcknowledged ?? this.relayDisclosureAcknowledged,
      dirty: dirty ?? this.dirty,
      dirtyRevision: dirtyRevision ?? this.dirtyRevision,
      lastAttemptedAt: lastAttemptedAt ?? this.lastAttemptedAt,
      lastAcceptedAt: lastAcceptedAt ?? this.lastAcceptedAt,
      verifiedHead: verifiedHead ?? this.verifiedHead,
      unsupportedNewerEnvelope: clearUnsupportedNewerEnvelope
          ? null
          : unsupportedNewerEnvelope ?? this.unsupportedNewerEnvelope,
      recoveryBlock: clearRecoveryBlock
          ? null
          : recoveryBlock ?? this.recoveryBlock,
    );
  }

  int _nextDirtyRevision() {
    if (dirtyRevision == WalletMetadataBackupLimits.maxSignedInt64) {
      throw StateError('wallet metadata dirty revision is exhausted');
    }
    return dirtyRevision + 1;
  }
}

int _latest(int? current, int candidate) {
  if (current == null || candidate > current) return candidate;
  return current;
}

void _validateEventId(String value, String name) {
  if (!_eventIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be lowercase 32-byte hex');
  }
}

void _validateNonNegativeInt64(int value, String name) {
  if (value < 0 || value > WalletMetadataBackupLimits.maxSignedInt64) {
    throw ArgumentError.value(value, name, 'must be a non-negative int64');
  }
}
