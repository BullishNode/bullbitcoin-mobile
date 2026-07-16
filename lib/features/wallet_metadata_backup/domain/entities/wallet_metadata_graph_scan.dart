import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';

enum WalletMetadataRelayRootQueryStatus { complete, partial, unavailable }

final class WalletMetadataRelayRootObservation {
  final WalletMetadataRelayUrl relayUrl;
  final WalletMetadataRelayRootQueryStatus status;
  final int authenticRootCount;

  WalletMetadataRelayRootObservation({
    required this.relayUrl,
    required this.status,
    required this.authenticRootCount,
  }) {
    if (authenticRootCount < 0 ||
        authenticRootCount >
            WalletMetadataBackupLimits.maxRootCandidatesPerRelay) {
      throw ArgumentError.value(authenticRootCount, 'authenticRootCount');
    }
    if (status == WalletMetadataRelayRootQueryStatus.unavailable &&
        authenticRootCount != 0) {
      throw ArgumentError('an unavailable relay cannot expose root events');
    }
  }
}

enum WalletMetadataRootFailureKind {
  unsupportedEnvelope,
  unreadableRoot,
  incompleteGraph,
  resourceLimit,
}

final class WalletMetadataRootFailureObservation {
  static final _eventIdPattern = RegExp(r'^[0-9a-f]{64}$');

  final String rootEventId;
  final int eventCreatedAt;
  final int? revision;
  final int? envelopeVersion;
  final WalletMetadataRootFailureKind kind;

  WalletMetadataRootFailureObservation({
    required this.rootEventId,
    required this.eventCreatedAt,
    required this.kind,
    this.revision,
    this.envelopeVersion,
  }) {
    if (!_eventIdPattern.hasMatch(rootEventId)) {
      throw ArgumentError.value(rootEventId, 'rootEventId');
    }
    if (eventCreatedAt < 0 ||
        eventCreatedAt > WalletMetadataBackupLimits.maxSignedInt64) {
      throw ArgumentError.value(eventCreatedAt, 'eventCreatedAt');
    }
    final authenticatedRevision = revision;
    if (authenticatedRevision != null &&
        (authenticatedRevision < 0 ||
            authenticatedRevision >
                WalletMetadataBackupLimits.maxSignedInt64)) {
      throw ArgumentError.value(revision, 'revision');
    }
    final unsupportedVersion = envelopeVersion;
    if ((kind == WalletMetadataRootFailureKind.unsupportedEnvelope) !=
            (unsupportedVersion != null) ||
        (unsupportedVersion != null &&
            (unsupportedVersion <= 1 ||
                unsupportedVersion >
                    WalletMetadataBackupLimits.maxSignedInt64))) {
      throw ArgumentError.value(envelopeVersion, 'envelopeVersion');
    }
  }

  bool couldBeNewerThan(WalletMetadataRemoteHead head) {
    final authenticatedRevision = revision;
    if (authenticatedRevision != null) {
      final byRevision = authenticatedRevision.compareTo(head.root.revision);
      if (byRevision != 0) return byRevision > 0;
    }
    final byCreatedAt = eventCreatedAt.compareTo(head.rootEventCreatedAt);
    if (byCreatedAt != 0) return byCreatedAt > 0;
    return rootEventId.compareTo(head.rootEventId) > 0;
  }
}

final class WalletMetadataGraphScan {
  final List<WalletMetadataRelayRootObservation> relayObservations;
  final List<WalletMetadataRemoteHead> completeHeads;
  final List<WalletMetadataRootFailureObservation> failures;
  final int? highestObservedRootCreatedAt;

  WalletMetadataGraphScan({
    required List<WalletMetadataRelayRootObservation> relayObservations,
    required List<WalletMetadataRemoteHead> completeHeads,
    required List<WalletMetadataRootFailureObservation> failures,
    required this.highestObservedRootCreatedAt,
  }) : relayObservations = List.unmodifiable(relayObservations),
       completeHeads = List.unmodifiable(completeHeads),
       failures = List.unmodifiable(failures) {
    if (this.relayObservations.isEmpty ||
        this.relayObservations.length > WalletMetadataBackupLimits.maxRelays ||
        this.relayObservations.map((item) => item.relayUrl).toSet().length !=
            this.relayObservations.length) {
      throw ArgumentError.value(relayObservations, 'relayObservations');
    }
    final completeIds = this.completeHeads
        .map((head) => head.rootEventId)
        .toSet();
    final failureIds = this.failures
        .map((failure) => failure.rootEventId)
        .toSet();
    if (completeIds.length != this.completeHeads.length ||
        failureIds.length != this.failures.length ||
        completeIds.intersection(failureIds).isNotEmpty) {
      throw ArgumentError('wallet metadata root observations overlap');
    }
    final highest = highestObservedRootCreatedAt;
    if ((highest == null) != (completeIds.isEmpty && failureIds.isEmpty) ||
        (highest != null &&
            (highest < 0 ||
                highest > WalletMetadataBackupLimits.maxSignedInt64))) {
      throw ArgumentError.value(
        highestObservedRootCreatedAt,
        'highestObservedRootCreatedAt',
      );
    }
  }

  bool get allRootQueriesComplete => relayObservations.every(
    (observation) =>
        observation.status == WalletMetadataRelayRootQueryStatus.complete,
  );

  bool get contactedAnyRelay => relayObservations.any(
    (observation) =>
        observation.status != WalletMetadataRelayRootQueryStatus.unavailable,
  );

  bool get sawAnyAuthenticRoot =>
      completeHeads.isNotEmpty || failures.isNotEmpty;

  WalletMetadataRemoteHead? get bestCompleteHead {
    if (completeHeads.isEmpty) return null;
    final sorted = completeHeads.toList(growable: false)
      ..sort(_compareHeadsNewestFirst);
    return sorted.first;
  }

  List<WalletMetadataRootFailureObservation> blockersNewerThan(
    WalletMetadataRemoteHead head,
  ) {
    final blockers =
        failures
            .where((failure) => failure.couldBeNewerThan(head))
            .toList(growable: false)
          ..sort(_compareFailuresNewestFirst);
    return blockers;
  }
}

int _compareHeadsNewestFirst(
  WalletMetadataRemoteHead left,
  WalletMetadataRemoteHead right,
) {
  final byRevision = right.root.revision.compareTo(left.root.revision);
  if (byRevision != 0) return byRevision;
  final byCreatedAt = right.rootEventCreatedAt.compareTo(
    left.rootEventCreatedAt,
  );
  if (byCreatedAt != 0) return byCreatedAt;
  return right.rootEventId.compareTo(left.rootEventId);
}

int _compareFailuresNewestFirst(
  WalletMetadataRootFailureObservation left,
  WalletMetadataRootFailureObservation right,
) {
  final leftRevision = left.revision;
  final rightRevision = right.revision;
  if (leftRevision != null && rightRevision != null) {
    final byRevision = rightRevision.compareTo(leftRevision);
    if (byRevision != 0) return byRevision;
  }
  final byCreatedAt = right.eventCreatedAt.compareTo(left.eventCreatedAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return right.rootEventId.compareTo(left.rootEventId);
}
