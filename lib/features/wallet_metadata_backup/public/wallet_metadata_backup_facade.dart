export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart'
    show WalletMetadataPublicationSuppression;

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart'
    as internal;
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/acknowledge_wallet_metadata_relay_disclosure_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/get_wallet_metadata_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:meta/meta.dart';

typedef _FetchRecoveryPlan =
    Future<
      Result<internal.WalletMetadataRecoveryResult, WalletMetadataBackupFailure>
    >
    Function({required String xprvBase58, required String parentFingerprint});
typedef _ApplyRecoveryPlan =
    Future<
      Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
    >
    Function({
      required internal.WalletMetadataRecoveryPlan plan,
      required Set<String> createdWalletRefs,
    });

/// Opaque recovery capability with only the summary needed by consumers.
///
/// Decrypted records, relay observations, and contributor intents remain
/// private to the wallet-metadata feature and can only be applied by the
/// facade API that produced this plan.
abstract interface class WalletMetadataRecoveryPlan {
  int get plannedRecordCount;

  int get unsupportedCount;

  int get invalidRecordCount;

  bool get isOlderRestore;
}

final class _WalletMetadataRecoveryPlanHandle
    implements WalletMetadataRecoveryPlan {
  final internal.WalletMetadataRecoveryPlan value;

  const _WalletMetadataRecoveryPlanHandle(this.value);

  @override
  int get plannedRecordCount => value.plannedRecordCount;

  @override
  int get unsupportedCount =>
      value.unsupportedRecords.length + value.unsupportedSections.length;

  @override
  int get invalidRecordCount => value.invalidRecords.length;

  @override
  bool get isOlderRestore => value.isOlderRestore;
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
    final status = switch ((plan.isOlderRestore, plan.unsupportedCount > 0)) {
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

class WalletMetadataBackupFacade {
  final GetWalletMetadataBackupStateUsecase _getState;
  final SetWalletMetadataBackupEnabledUsecase _setEnabled;
  final AcknowledgeWalletMetadataRelayDisclosureUsecase _acknowledgeDisclosure;
  final MarkWalletMetadataBackupDirtyUsecase _markDirty;
  final WalletMetadataBackupCoordinator _coordinator;
  final _FetchRecoveryPlan _fetchRecoveryPlan;
  final _ApplyRecoveryPlan _applyRecoveryPlan;

  const WalletMetadataBackupFacade(
    this._getState,
    this._setEnabled,
    this._acknowledgeDisclosure,
    this._markDirty,
    this._coordinator,
    this._fetchRecoveryPlan,
    this._applyRecoveryPlan,
  );

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  getState() {
    return _getState.execute();
  }

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  setEnabled(bool enabled) async {
    final result = await _setEnabled.execute(enabled);
    if (result case Ok(:final value) when value.enabled) {
      _coordinator.scheduleRetry();
    }
    return result;
  }

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  acknowledgeRelayDisclosure() async {
    final result = await _acknowledgeDisclosure.execute();
    if (result case Ok()) _coordinator.scheduleRetry();
    return result;
  }

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  markDirty() async {
    final result = await _markDirty.execute();
    if (result case Ok()) _coordinator.scheduleRetry();
    return result;
  }

  @useResult
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  backupNow() {
    return _coordinator.publishNow();
  }

  Future<void> retryPendingBackup() => _coordinator.retryBestEffort();

  Future<T> suppressPublicationWhile<T>(Future<T> Function() action) {
    return _coordinator.suppressPublicationWhile(action);
  }

  Future<WalletMetadataPublicationSuppression> beginRecoverySession() {
    return _coordinator.beginRecoverySession();
  }

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  fetchRecoveryPlan({
    required String xprvBase58,
    required String parentFingerprint,
  }) async {
    final result = await _fetchRecoveryPlan(
      xprvBase58: xprvBase58,
      parentFingerprint: parentFingerprint,
    );
    return result.map(_toPublicRecoveryResult);
  }

  @useResult
  Future<Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>>
  applyRecoveryPlan({
    required WalletMetadataRecoveryPlan plan,
    required Set<String> createdWalletRefs,
  }) {
    if (plan is! _WalletMetadataRecoveryPlanHandle) {
      return Future.value(const Err(WalletMetadataBackupEncodingFailure()));
    }
    return _coordinator.suppressPublicationWhile(
      () => _applyRecoveryPlan(
        plan: plan.value,
        createdWalletRefs: createdWalletRefs,
      ),
    );
  }
}

WalletMetadataRecoveryResult _toPublicRecoveryResult(
  internal.WalletMetadataRecoveryResult result,
) {
  switch (result.status) {
    case internal.WalletMetadataRecoveryStatus.latestSnapshot ||
        internal
            .WalletMetadataRecoveryStatus
            .latestSnapshotWithUnsupportedMetadata ||
        internal.WalletMetadataRecoveryStatus.olderSnapshot ||
        internal
            .WalletMetadataRecoveryStatus
            .olderSnapshotWithUnsupportedMetadata:
      final plan = result.plan;
      if (plan == null) {
        throw StateError('Ready wallet metadata recovery result lacks a plan');
      }
      return WalletMetadataRecoveryResult.ready(
        _WalletMetadataRecoveryPlanHandle(plan),
      );
    case internal.WalletMetadataRecoveryStatus.noSnapshotFound:
      return const WalletMetadataRecoveryResult.noSnapshotFound();
    case internal.WalletMetadataRecoveryStatus.relaysUnavailable:
      return const WalletMetadataRecoveryResult.relaysUnavailable();
    case internal.WalletMetadataRecoveryStatus.noCompleteSnapshot:
      return const WalletMetadataRecoveryResult.noCompleteSnapshot();
    case internal.WalletMetadataRecoveryStatus.unsupportedNewerEnvelope:
      return const WalletMetadataRecoveryResult.unsupportedNewerEnvelope();
  }
}
