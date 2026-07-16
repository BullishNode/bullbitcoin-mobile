import 'package:bb_mobile/core/utils/clock.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_graph_scan.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publication.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_safe_head.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_graph_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/repositories/wallet_metadata_safe_head_repository.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_limits.dart';
import 'package:meta/meta.dart';

final class WalletMetadataSafeHeadRepositoryImpl
    implements WalletMetadataSafeHeadRepository {
  final WalletMetadataGraphRepository _graphRepository;
  final Clock _clock;

  const WalletMetadataSafeHeadRepositoryImpl({
    required this._graphRepository,
    this._clock = const SystemClock(),
  });

  @override
  @useResult
  Future<Result<WalletMetadataSafeHeadResult, WalletMetadataBackupFailure>>
  fetchForPublication({
    required String xprvBase58,
    required String parentFingerprint,
    required List<WalletMetadataRelayUrl> relayUrls,
  }) async {
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
    if (!scan.allRootQueriesComplete) {
      return const Ok(WalletMetadataSafeHeadUnavailable());
    }

    final best = scan.bestCompleteHead;
    final blockers = best == null
        ? scan.failures
        : scan.blockersNewerThan(best);
    final unsupported = _newestUnsupported(blockers);
    if (unsupported != null) {
      final observedAt = _clock.nowSecs();
      if (observedAt < 0 ||
          observedAt > WalletMetadataBackupLimits.maxSignedInt64) {
        return const Err(WalletMetadataBackupClockFailure());
      }
      return Ok(
        WalletMetadataSafeHeadUnsupported(
          WalletMetadataBackupUnsupportedEnvelope(
            rootEventId: unsupported.rootEventId,
            envelopeVersion: unsupported.envelopeVersion!,
            eventCreatedAt: unsupported.eventCreatedAt,
            observedAt: observedAt,
          ),
        ),
      );
    }
    if (best == null) {
      return scan.sawAnyAuthenticRoot
          ? const Ok(WalletMetadataSafeHeadIncomplete())
          : const Ok(WalletMetadataSafeHeadNoSnapshot());
    }
    if (blockers.isNotEmpty) {
      return const Ok(WalletMetadataSafeHeadIncomplete());
    }
    return Ok(WalletMetadataSafeHeadCompatible(best));
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
}
