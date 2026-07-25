// ignore_for_file: prefer_initializing_formals

export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_backup_state.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_publish_outcome.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

typedef UnifiedWalletBackupStateReader =
    Future<Result<WalletMetadataBackupState, Object?>> Function();
typedef UnifiedWalletBackupAction = Future<Result<void, Object?>> Function();
typedef UnifiedWalletBackupEnable =
    Future<Result<void, Object?>> Function(bool enabled);
typedef UnifiedWalletBackupRecovery =
    Future<WalletMetadataRecoveryFence> Function();

abstract interface class WalletMetadataRecoverySession {
  bool get isClosed;

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs});

  void close();
}

class WalletMetadataBackupFacade {
  final UnifiedWalletBackupStateReader _getWalletState;
  final UnifiedWalletBackupEnable _setWalletEnabled;
  final UnifiedWalletBackupAction _backupNow;
  final UnifiedWalletBackupAction _deleteRemote;
  final UnifiedWalletBackupRecovery _beginRecovery;
  final WalletMetadataBackupSectionProvider _sectionProvider;

  const WalletMetadataBackupFacade({
    required UnifiedWalletBackupStateReader getWalletState,
    required UnifiedWalletBackupEnable setWalletEnabled,
    required UnifiedWalletBackupAction backupNow,
    required UnifiedWalletBackupAction deleteRemote,
    required UnifiedWalletBackupRecovery beginRecovery,
    required WalletMetadataBackupSectionProvider sectionProvider,
  }) : _getWalletState = getWalletState,
       _setWalletEnabled = setWalletEnabled,
       _backupNow = backupNow,
       _deleteRemote = deleteRemote,
       _beginRecovery = beginRecovery,
       _sectionProvider = sectionProvider;

  const WalletMetadataBackupFacade.unified({
    required UnifiedWalletBackupStateReader getWalletState,
    required UnifiedWalletBackupEnable setWalletEnabled,
    required UnifiedWalletBackupAction backupNow,
    required UnifiedWalletBackupAction deleteRemote,
    required UnifiedWalletBackupRecovery beginRecovery,
    required WalletMetadataBackupSectionProvider sectionProvider,
  }) : this(
         getWalletState: getWalletState,
         setWalletEnabled: setWalletEnabled,
         backupNow: backupNow,
         deleteRemote: deleteRemote,
         beginRecovery: beginRecovery,
         sectionProvider: sectionProvider,
       );

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  getState() async => (await _getWalletState()).mapErr(_mapFailure);

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  setEnabled(bool enabled) async => (await _setWalletEnabled(enabled))
      .map((_) => WalletMetadataBackupState.initial.withEnabled(enabled))
      .mapErr(_mapFailure);

  @useResult
  Future<Result<WalletMetadataBackupState, WalletMetadataBackupFailure>>
  markDirty() => getState();

  @useResult
  Future<Result<WalletMetadataPublishOutcome, WalletMetadataBackupFailure>>
  backupNow() async => (await _backupNow())
      .map(
        (_) => const WalletMetadataPublishOutcome(
          status: WalletMetadataPublishStatus.stored,
        ),
      )
      .mapErr(_mapFailure);

  @useResult
  Future<Result<void, WalletMetadataBackupFailure>>
  deleteRemoteBackup() async => (await _deleteRemote()).mapErr(_mapFailure);

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recoverSection({
    required String payload,
    required Set<String> createdWalletRefs,
  }) async => (await _sectionProvider.recoverSection(
    payload: payload,
    createdWalletRefs: createdWalletRefs,
  )).map(WalletMetadataRecoveryResult.applied);

  Future<WalletMetadataRecoverySession> beginRecoverySession() async =>
      _UnifiedRecoverySession(await _beginRecovery());

  WalletMetadataBackupFailure _mapFailure(Object? failure) =>
      failure is WalletMetadataBackupFailure
      ? failure
      : WalletMetadataBackupRemoteFailure(failure.runtimeType.toString());
}

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
  ) => WalletMetadataRecoveryResult._(
    status: result.publicationBlocked
        ? WalletMetadataRecoveryStatus.partiallyRecovered
        : WalletMetadataRecoveryStatus.recovered,
    applyResult: result,
  );

  const WalletMetadataRecoveryResult.noSnapshotFound()
    : this._(status: WalletMetadataRecoveryStatus.noSnapshotFound);
}

final class _UnifiedRecoverySession implements WalletMetadataRecoverySession {
  final WalletMetadataRecoveryFence _lease;
  bool _closed = false;

  _UnifiedRecoverySession(this._lease);

  @override
  bool get isClosed => _closed;

  @override
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs}) async =>
      const Ok(WalletMetadataRecoveryResult.noSnapshotFound());

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _lease.close();
  }
}
