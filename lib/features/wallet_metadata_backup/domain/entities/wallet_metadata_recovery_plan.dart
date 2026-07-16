import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_snapshot.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';

final class WalletMetadataContributorImportPlan {
  final String contributorType;
  final List<int> sectionVersions;
  final List<WalletMetadataImportIntent> intents;

  WalletMetadataContributorImportPlan({
    required this.contributorType,
    required List<int> sectionVersions,
    required List<WalletMetadataImportIntent> intents,
  }) : sectionVersions = List.unmodifiable(sectionVersions),
       intents = List.unmodifiable(intents) {
    if (contributorType.isEmpty ||
        this.sectionVersions.isEmpty ||
        this.intents.any(
          (intent) => intent.contributorType != contributorType,
        )) {
      throw ArgumentError('wallet metadata contributor plan is invalid');
    }
  }
}

final class WalletMetadataInvalidRecord {
  final String recordType;
  final int recordVersion;
  final WalletMetadataRecordInvalidReason reason;

  const WalletMetadataInvalidRecord({
    required this.recordType,
    required this.recordVersion,
    required this.reason,
  });
}

final class WalletMetadataRecoveryPlan {
  final WalletMetadataRemoteHead selectedHead;
  final List<WalletMetadataContributorImportPlan> contributorPlans;
  final List<WalletMetadataRecord> unsupportedRecords;
  final List<WalletMetadataSection> unsupportedSections;
  final List<WalletMetadataInvalidRecord> invalidRecords;
  final List<WalletMetadataRootFailureObservation> newerRootFailures;
  final bool relayCoverageComplete;

  WalletMetadataRecoveryPlan({
    required this.selectedHead,
    required List<WalletMetadataContributorImportPlan> contributorPlans,
    required List<WalletMetadataRecord> unsupportedRecords,
    required List<WalletMetadataSection> unsupportedSections,
    required List<WalletMetadataInvalidRecord> invalidRecords,
    required List<WalletMetadataRootFailureObservation> newerRootFailures,
    required this.relayCoverageComplete,
  }) : contributorPlans = List.unmodifiable(contributorPlans),
       unsupportedRecords = List.unmodifiable(unsupportedRecords),
       unsupportedSections = List.unmodifiable(unsupportedSections),
       invalidRecords = List.unmodifiable(invalidRecords),
       newerRootFailures = List.unmodifiable(newerRootFailures) {
    if (this.contributorPlans
            .map((plan) => plan.contributorType)
            .toSet()
            .length !=
        this.contributorPlans.length) {
      throw ArgumentError('wallet metadata contributor plans repeat a type');
    }
  }

  bool get isOlderRestore =>
      !relayCoverageComplete || newerRootFailures.isNotEmpty;

  bool get hasUnsupportedMetadata =>
      unsupportedRecords.isNotEmpty || unsupportedSections.isNotEmpty;

  int get plannedRecordCount =>
      contributorPlans.fold<int>(0, (sum, plan) => sum + plan.intents.length);
}

enum WalletMetadataRecoveryStatus {
  latestSnapshot,
  latestSnapshotWithUnsupportedMetadata,
  olderSnapshot,
  olderSnapshotWithUnsupportedMetadata,
  noSnapshotFound,
  relaysUnavailable,
  noCompleteSnapshot,
  unsupportedNewerEnvelope,
}

final class WalletMetadataRecoveryResult {
  final WalletMetadataRecoveryStatus status;
  final WalletMetadataRecoveryPlan? plan;

  const WalletMetadataRecoveryResult._({required this.status, this.plan});

  factory WalletMetadataRecoveryResult.ready(WalletMetadataRecoveryPlan plan) {
    final status = switch ((plan.isOlderRestore, plan.hasUnsupportedMetadata)) {
      (false, false) => WalletMetadataRecoveryStatus.latestSnapshot,
      (false, true) =>
        WalletMetadataRecoveryStatus.latestSnapshotWithUnsupportedMetadata,
      (true, false) => WalletMetadataRecoveryStatus.olderSnapshot,
      (true, true) =>
        WalletMetadataRecoveryStatus.olderSnapshotWithUnsupportedMetadata,
    };
    return WalletMetadataRecoveryResult._(status: status, plan: plan);
  }

  const WalletMetadataRecoveryResult.noSnapshotFound()
    : this._(status: WalletMetadataRecoveryStatus.noSnapshotFound);

  const WalletMetadataRecoveryResult.relaysUnavailable()
    : this._(status: WalletMetadataRecoveryStatus.relaysUnavailable);

  const WalletMetadataRecoveryResult.noCompleteSnapshot()
    : this._(status: WalletMetadataRecoveryStatus.noCompleteSnapshot);

  const WalletMetadataRecoveryResult.unsupportedNewerEnvelope()
    : this._(status: WalletMetadataRecoveryStatus.unsupportedNewerEnvelope);
}
