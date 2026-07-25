// ignore_for_file: prefer_initializing_formals

export 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
export 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';

import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/entities/wallet_metadata_apply.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/domain/wallet_metadata_backup_failure.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_section_provider.dart';
import 'package:meta/meta.dart';

typedef UnifiedWalletBackupEnable =
    Future<Result<void, Object?>> Function(bool enabled);
typedef UnifiedWalletBackupRecovery =
    Future<WalletMetadataRecoveryFence> Function();
typedef UnifiedWalletBackupRecoveryBlock =
    Future<Result<void, Object?>> Function(bool blocked);

abstract interface class WalletMetadataRecoverySession {
  bool get isClosed;

  @useResult
  Future<Result<WalletMetadataRecoveryResult, WalletMetadataBackupFailure>>
  recover({required Set<String> createdWalletRefs});

  void close();
}

class WalletMetadataBackupFacade {
  final UnifiedWalletBackupEnable _setWalletEnabled;
  final UnifiedWalletBackupRecovery _beginRecovery;
  final UnifiedWalletBackupRecoveryBlock _setRecoveryBlocked;
  final WalletMetadataBackupSectionProvider _sectionProvider;

  const WalletMetadataBackupFacade({
    required UnifiedWalletBackupEnable setWalletEnabled,
    required UnifiedWalletBackupRecovery beginRecovery,
    required UnifiedWalletBackupRecoveryBlock setRecoveryBlocked,
    required WalletMetadataBackupSectionProvider sectionProvider,
  }) : _setWalletEnabled = setWalletEnabled,
       _beginRecovery = beginRecovery,
       _setRecoveryBlocked = setRecoveryBlocked,
       _sectionProvider = sectionProvider;

  const WalletMetadataBackupFacade.unified({
    required UnifiedWalletBackupEnable setWalletEnabled,
    required UnifiedWalletBackupRecovery beginRecovery,
    required UnifiedWalletBackupRecoveryBlock setRecoveryBlocked,
    required WalletMetadataBackupSectionProvider sectionProvider,
  }) : this(
         setWalletEnabled: setWalletEnabled,
         beginRecovery: beginRecovery,
         setRecoveryBlocked: setRecoveryBlocked,
         sectionProvider: sectionProvider,
       );

  @useResult
  Future<Result<void, WalletMetadataBackupFailure>> setEnabled(
    bool enabled,
  ) async => (await _setWalletEnabled(enabled)).mapErr(_mapFailure);

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

  @useResult
  Future<Result<void, WalletMetadataBackupFailure>> setRecoveryBlocked(
    bool blocked,
  ) async => (await _setRecoveryBlocked(blocked)).mapErr(_mapFailure);

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
