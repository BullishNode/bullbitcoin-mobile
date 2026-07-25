export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_recovery_plan.dart'
    as internal;
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/delete_wallet_metadata_backup_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/get_wallet_metadata_backup_state_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/mark_wallet_metadata_backup_dirty_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/usecases/set_wallet_metadata_backup_enabled_usecase.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_publication_guard.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/watchers/wallet_metadata_backup_coordinator.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
// ignore_for_file: prefer_initializing_formals

import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

typedef _FetchRecoveryPlan =
    Future<
      Result<internal.WalletMetadataRecoveryResult, WalletMetadataBackupFailure>
    >
    Function();
typedef _ApplyRecoveryPlan =
    Future<
      Result<WalletMetadataRecoveryApplyResult, WalletMetadataBackupFailure>
    >
    Function({
      required internal.WalletMetadataRecoveryPlan plan,
      required Set<String> createdWalletRefs,
    });
typedef _RecoverMetadata =
    Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
    Function(Set<String> createdWalletRefs);

enum WalletMetadataRecoveryStatus {
  recovered,
  partiallyRecovered,
  noSnapshotFound,
  remoteUnavailable,
  unsupportedNewerEnvelope,
}

final class WalletMetadataRecoveryResult {
  final WalletMetadataRecoveryStatus status;
  final WalletMetadataRecoveryApplyResult? applyResult;

  const WalletMetadataRecoveryResult._({
    required this.status,
    this.applyResult,
  });

  factory WalletMetadataRecoveryResult.applied(
    WalletMetadataRecoveryApplyResult result,
  ) {
    return WalletMetadataRecoveryResult._(
      status: result.publicationBlocked
          ? WalletMetadataRecoveryStatus.partiallyRecovered
          : WalletMetadataRecoveryStatus.recovered,
      applyResult: result,
    );
  }

  const WalletMetadataRecoveryResult.noSnapshotFound()
    : this._(status: WalletMetadataRecoveryStatus.noSnapshotFound);

  const WalletMetadataRecoveryResult.remoteUnavailable()
    : this._(status: WalletMetadataRecoveryStatus.remoteUnavailable);

  const WalletMetadataRecoveryResult.unsupportedNewerEnvelope()
    : this._(status: WalletMetadataRecoveryStatus.unsupportedNewerEnvelope);
}

abstract interface class WalletMetadataRecoverySession {
  bool get isClosed;

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs});

  void close();
}

final class _WalletMetadataRecoverySession
    implements WalletMetadataRecoverySession {
  WalletMetadataPublicationSuppression? _suppression;
  final _RecoverMetadata _recover;
  final WalletMetadataBackupFailure? _preflightFailure;
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>?
  _inFlight;
  bool _closeRequested = false;

  _WalletMetadataRecoverySession(
    this._suppression,
    this._recover, {
    this._preflightFailure,
  });

  @override
  bool get isClosed => _closeRequested || _suppression == null;

  @override
  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs}) async {
    if (isClosed || _inFlight != null) {
      return Future.value(const Err(WalletMetadataBackupEncodingFailure()));
    }
    final preflightFailure = _preflightFailure;
    if (preflightFailure != null) {
      return Err(preflightFailure);
    }
    final recovery = _recover(Set.unmodifiable(createdWalletRefs));
    _inFlight = recovery;
    try {
      return await recovery;
    } finally {
      if (identical(_inFlight, recovery)) _inFlight = null;
      if (_closeRequested) _releaseSuppression();
    }
  }

  @override
  void close() {
    _closeRequested = true;
    if (_inFlight == null) _releaseSuppression();
  }

  void _releaseSuppression() {
    _suppression?.close();
    _suppression = null;
  }
}

WalletMetadataBackupState _metadataStateFromEnabled(bool enabled) =>
    WalletMetadataBackupState.initial.withEnabled(enabled);

WalletMetadataBackupState _metadataStateFromWalletState(
  WalletBackupState state,
) => WalletMetadataBackupState(
  enabled: state.enabled,
  dirty: state.dirty,
  dirtyRevision: state.dirtyRevision,
  lastAttemptedAt: state.lastAttemptedAt,
  lastSucceededAt: state.lastSucceededAt,
  verifiedHead: state.remoteGeneration == 0
      ? null
      : WalletMetadataBackupVerifiedHead(
          remoteGeneration: state.remoteGeneration,
          remoteEtag: state.remoteEtag!,
          snapshotRevision: 0,
          canonicalContentHash: state.contentHash!,
          verifiedAt: state.lastSucceededAt!,
        ),
  unsupportedNewerEnvelope: state.unsupportedVersion == null
      ? null
      : WalletMetadataBackupUnsupportedEnvelope(
          remoteGeneration: 1,
          remoteEtag: state.remoteEtag ?? _zeroHash,
          envelopeVersion: state.unsupportedVersion!,
          observedAt: state.lastAttemptedAt ?? 0,
        ),
  recoveryBlock: null,
);

const _zeroHash =
    '0000000000000000000000000000000000000000000000000000000000000000';

class WalletMetadataBackupFacade {
  final GetWalletMetadataBackupStateUsecase? _getState;
  final SetWalletMetadataBackupEnabledUsecase? _setEnabled;
  final MarkWalletMetadataBackupDirtyUsecase? _markDirty;
  final DeleteWalletMetadataBackupUsecase? _deleteRemote;
  final WalletMetadataBackupCoordinator? _coordinator;
  final _FetchRecoveryPlan? _fetchRecoveryPlan;
  final _ApplyRecoveryPlan? _applyRecoveryPlan;
  final WalletBackupFacade? _walletBackup;
  final WalletMetadataBackupSectionProvider? _sectionProvider;

  const WalletMetadataBackupFacade(
    this._getState,
    this._setEnabled,
    this._markDirty,
    this._deleteRemote,
    this._coordinator,
    this._fetchRecoveryPlan,
    this._applyRecoveryPlan, {
    WalletBackupFacade? walletBackup,
    WalletMetadataBackupSectionProvider? sectionProvider,
  }) : _walletBackup = walletBackup,
       _sectionProvider = sectionProvider;

  const WalletMetadataBackupFacade.unified({
    required WalletBackupFacade walletBackup,
    required WalletMetadataBackupSectionProvider sectionProvider,
  }) : _getState = null,
       _setEnabled = null,
       _markDirty = null,
       _deleteRemote = null,
       _coordinator = null,
       _fetchRecoveryPlan = null,
       _applyRecoveryPlan = null,
       _walletBackup = walletBackup,
       _sectionProvider = sectionProvider;

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  getState() async {
    final walletBackup = _walletBackup;
    if (walletBackup == null) return _getState!.execute();
    final result = await walletBackup.getState();
    return result
        .map(_metadataStateFromWalletState)
        .mapErr(
          (failure) =>
              WalletMetadataBackupRemoteFailure(failure.runtimeType.toString()),
        );
  }

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  setEnabled(bool enabled) async {
    final walletBackup = _walletBackup;
    if (walletBackup != null) {
      final result = await walletBackup.setEnabled(enabled);
      return result
          .map((_) => _metadataStateFromEnabled(enabled))
          .mapErr(
            (failure) => WalletMetadataBackupRemoteFailure(
              failure.runtimeType.toString(),
            ),
          );
    }
    final setEnabled = _setEnabled!;
    final coordinator = _coordinator!;
    final result = enabled
        ? await setEnabled.execute(true)
        : await coordinator.suppressPublicationWhile(
            () => setEnabled.execute(false),
          );
    if (result case Ok(value: WalletMetadataBackupState(enabled: true))) {
      coordinator.scheduleFallbackRetry();
    }
    return result;
  }

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  markDirty() async {
    final walletBackup = _walletBackup;
    if (walletBackup != null) {
      return const Ok(WalletMetadataBackupState.initial);
    }
    return _markDirty!.execute();
  }

  @useResult
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  backupNow() async {
    final walletBackup = _walletBackup;
    if (walletBackup == null) return _coordinator!.publishNow();
    final result = await walletBackup.backupNow();
    return result
        .map(
          (_) => const WalletMetadataPublishOutcome(
            status: WalletMetadataPublishStatus.stored,
          ),
        )
        .mapErr(
          (failure) =>
              WalletMetadataBackupRemoteFailure(failure.runtimeType.toString()),
        );
  }

  @useResult
  Future<Result<void, WalletMetadataBackupFailure>> deleteRemoteBackup() async {
    final walletBackup = _walletBackup;
    if (walletBackup != null) {
      final result = await walletBackup.deleteRemoteBackup(confirmed: true);
      return result.mapErr(
        (failure) =>
            WalletMetadataBackupRemoteFailure(failure.runtimeType.toString()),
      );
    }
    return _coordinator!.suppressPublicationWhile(_deleteRemote!.execute);
  }

  Future<void> retryPendingBackup() async {
    if (_walletBackup != null) return;
    await _coordinator!.retryBestEffort();
  }

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recoverSection({
    required String payload,
    required Set<String> createdWalletRefs,
  }) async {
    final provider = _sectionProvider;
    if (provider == null) return _recoverMetadata(createdWalletRefs);
    final result = await provider.recoverSection(
      payload: payload,
      createdWalletRefs: createdWalletRefs,
    );
    return result.map(WalletMetadataRecoveryResult.applied);
  }

  Future<WalletMetadataRecoverySession> beginRecoverySession() async {
    if (_walletBackup != null) return const _UnifiedRecoverySession();
    final acquisition = await _coordinator!.beginRecoverySession();
    return _WalletMetadataRecoverySession(
      acquisition.suppression,
      _recoverMetadata,
      preflightFailure: acquisition.failure,
    );
  }

  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  _recoverMetadata(Set<String> createdWalletRefs) async {
    final fetched = await _fetchRecoveryPlan!();
    final internal.WalletMetadataRecoveryResult recovery;
    switch (fetched) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        recovery = value;
    }
    switch (recovery.status) {
      case internal.WalletMetadataRecoveryStatus.snapshot ||
          internal.WalletMetadataRecoveryStatus.snapshotWithUnsupportedMetadata:
        final plan = recovery.plan;
        if (plan == null) {
          return const Err(WalletMetadataBackupEncodingFailure());
        }
        final applied = await _applyRecoveryPlan!(
          plan: plan,
          createdWalletRefs: createdWalletRefs,
        );
        return applied.map(WalletMetadataRecoveryResult.applied);
      case internal.WalletMetadataRecoveryStatus.noSnapshotFound:
        return const Ok(WalletMetadataRecoveryResult.noSnapshotFound());
      case internal.WalletMetadataRecoveryStatus.remoteUnavailable:
        return const Ok(WalletMetadataRecoveryResult.remoteUnavailable());
      case internal.WalletMetadataRecoveryStatus.unsupportedNewerEnvelope:
        return const Ok(
          WalletMetadataRecoveryResult.unsupportedNewerEnvelope(),
        );
    }
  }
}

final class _UnifiedRecoverySession implements WalletMetadataRecoverySession {
  const _UnifiedRecoverySession();

  @override
  bool get isClosed => false;

  @override
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs}) async =>
      const Ok(WalletMetadataRecoveryResult.noSnapshotFound());

  @override
  void close() {}
}
