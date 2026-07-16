import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/nostr_relay_policy/public/nostr_relay_policy_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_record.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_backup_state_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_contributor.dart';
import 'package:meta/meta.dart';

final class FetchWalletMetadataRecoveryPlanUsecase {
  final WalletMetadataBackupStateRepository _stateRepository;
  final WalletMetadataGraphRepository _graphRepository;
  final List<WalletMetadataContributor> _contributors;
  final NostrRelayPolicyFacade _relayPolicy;
  final Clock _clock;

  FetchWalletMetadataRecoveryPlanUsecase({
    required this._stateRepository,
    required this._graphRepository,
    required List<WalletMetadataContributor> contributors,
    this._relayPolicy = const NostrRelayPolicyFacade(),
    this._clock = const SystemClock(),
  }) : _contributors = List.unmodifiable(contributors) {
    final types = _contributors.map((contributor) => contributor.recordType);
    if (_contributors.isEmpty || types.toSet().length != _contributors.length) {
      throw ArgumentError.value(contributors, 'contributors');
    }
  }

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  execute({
    required String xprvBase58,
    required String parentFingerprint,
  }) async {
    final relayUrls = _relayPolicy
        .getPolicy()
        .defaultRelays
        .map((relay) => WalletMetadataRelayUrl(relay.url))
        .toSet()
        .toList(growable: false);
    if (relayUrls.isEmpty) {
      return const Err(WalletMetadataBackupRelayFailure());
    }
    final scanResult = await _graphRepository.fetch(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
      relayUrls: relayUrls,
    );
    final WalletMetadataGraphScan scan;
    switch (scanResult) {
      case Ok(:final value):
        scan = value;
      case Err(:final failure):
        return Err(failure);
    }

    final selected = scan.bestCompleteHead;
    if (selected == null) {
      final unsupported = _newestUnsupported(scan.failures);
      if (unsupported != null) {
        final persisted = await _persistUnsupported(unsupported);
        if (persisted case Err(:final failure)) return Err(failure);
        return const Ok(
          WalletMetadataRecoveryResult.unsupportedNewerEnvelope(),
        );
      }
      if (!scan.contactedAnyRelay || !scan.allRootQueriesComplete) {
        return const Ok(WalletMetadataRecoveryResult.relaysUnavailable());
      }
      return scan.sawAnyAuthenticRoot
          ? const Ok(WalletMetadataRecoveryResult.noCompleteSnapshot())
          : const Ok(WalletMetadataRecoveryResult.noSnapshotFound());
    }

    final newerFailures = scan.blockersNewerThan(selected);
    final unsupported = _newestUnsupported(newerFailures);
    if (unsupported != null) {
      final persisted = await _persistUnsupported(unsupported);
      if (persisted case Err(:final failure)) return Err(failure);
    }
    final plan = _buildPlan(
      selected: selected,
      newerFailures: newerFailures,
      relayCoverageComplete: scan.allRootQueriesComplete,
    );
    return Ok(WalletMetadataRecoveryResult.ready(plan));
  }

  WalletMetadataRecoveryPlan _buildPlan({
    required WalletMetadataRemoteHead selected,
    required List<WalletMetadataRootFailureObservation> newerFailures,
    required bool relayCoverageComplete,
  }) {
    final contributorsByType = {
      for (final contributor in _contributors)
        contributor.recordType: contributor,
    };
    final intentsByType = <String, List<WalletMetadataImportIntent>>{};
    final invalidRecords = <WalletMetadataInvalidRecord>[];
    final unsupportedRecords = <WalletMetadataRecord>[];
    for (final record in selected.records) {
      final contributor = contributorsByType[record.type];
      if (contributor == null ||
          !contributor.supportedVersions.contains(record.version)) {
        unsupportedRecords.add(record);
        continue;
      }
      switch (contributor.validateRecord(record)) {
        case WalletMetadataRecordValid(:final intent):
          intentsByType.putIfAbsent(record.type, () => []).add(intent);
        case WalletMetadataRecordInvalid(:final reason):
          invalidRecords.add(
            WalletMetadataInvalidRecord(
              recordType: record.type,
              recordVersion: record.version,
              reason: reason,
            ),
          );
      }
    }

    final unsupportedSections = selected.root.sections
        .where((section) {
          final contributor = contributorsByType[section.type];
          return contributor == null ||
              section.versions.any(
                (version) => !contributor.supportedVersions.contains(version),
              );
        })
        .toList(growable: false);
    final contributorPlans = selected.root.sections
        .map((section) {
          final contributor = contributorsByType[section.type];
          if (contributor == null) return null;
          final supportedSectionVersions = section.versions
              .where(contributor.supportedVersions.contains)
              .toList(growable: false);
          if (supportedSectionVersions.isEmpty) return null;
          return WalletMetadataContributorImportPlan(
            contributorType: section.type,
            sectionVersions: supportedSectionVersions,
            intents: intentsByType[section.type] ?? const [],
          );
        })
        .nonNulls
        .toList(growable: false);
    return WalletMetadataRecoveryPlan(
      selectedHead: selected,
      contributorPlans: contributorPlans,
      unsupportedRecords: unsupportedRecords,
      unsupportedSections: unsupportedSections,
      invalidRecords: invalidRecords,
      newerRootFailures: newerFailures,
      relayCoverageComplete: relayCoverageComplete,
    );
  }

  WalletMetadataRootFailureObservation? _newestUnsupported(
    List<WalletMetadataRootFailureObservation> failures,
  ) {
    final unsupported =
        failures
            .where(
              (failure) =>
                  failure.kind ==
                  WalletMetadataRootFailureKind.unsupportedEnvelope,
            )
            .toList(growable: false)
          ..sort((left, right) {
            final byCreatedAt = right.eventCreatedAt.compareTo(
              left.eventCreatedAt,
            );
            if (byCreatedAt != 0) return byCreatedAt;
            return right.rootEventId.compareTo(left.rootEventId);
          });
    return unsupported.firstOrNull;
  }

  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  _persistUnsupported(WalletMetadataRootFailureObservation unsupported) {
    final observedAt = _clock.nowSecs();
    if (observedAt < 0 ||
        observedAt > WalletMetadataBackupLimits.maxSignedInt64) {
      return Future.value(const Err(WalletMetadataBackupClockFailure()));
    }
    return _stateRepository.update(
      (state) => state.recordUnsupportedNewerEnvelope(
        WalletMetadataBackupUnsupportedEnvelope(
          rootEventId: unsupported.rootEventId,
          envelopeVersion: unsupported.envelopeVersion!,
          eventCreatedAt: unsupported.eventCreatedAt,
          observedAt: observedAt,
        ),
      ),
    );
  }
}
