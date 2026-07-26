import 'package:bb_mobile/core/utils/logger.dart';
import 'package:bb_mobile/core/utils/result.dart';
import 'package:bb_mobile/features/remote_keychain_recovery/domain/remote_keychain_recovery_result.dart';
import 'package:bb_mobile/features/wallet_backup/public/wallet_backup_facade.dart';
import 'package:bb_mobile/features/wallet_metadata_backup/public/wallet_metadata_backup_facade.dart';

typedef _RecoverKeychain = Future<RemoteKeychainRecoveryResult> Function();

final class RecoverRemoteWalletBackupsUsecase {
  final _RecoverKeychain _recoverKeychain;
  final WalletBackupFacade _walletBackup;
  final WalletMetadataBackupFacade _metadataBackup;

  const RecoverRemoteWalletBackupsUsecase(
    this._recoverKeychain,
    this._walletBackup,
    this._metadataBackup,
  );

  Future<RemoteKeychainRecoveryResult> execute({
    required Set<String> defaultCreatedWalletIds,
  }) async {
    WalletBackupLifecycleLease? lease;
    Object? keychainError;
    StackTrace? keychainStack;
    RemoteKeychainRecoveryResult? keychainResult;
    var metadataComplete = true;
    WalletBackupRemoteIdentity initialRemoteIdentity;

    lease = await _walletBackup.beginRecoveryLease();
    try {
      _requireOk(
        await _walletBackup.setRecoveryBlocked(true),
        'persist recovery block before restore',
      );
      initialRemoteIdentity = _requireValue(
        await _walletBackup.fetchRemoteIdentity(),
        'capture remote checkpoint before restore',
      );

      try {
        keychainResult = await _recoverKeychain();
      } on Exception catch (error, stack) {
        keychainError = error;
        keychainStack = stack;
      }

      final metadataPayload = keychainResult?.metadataPayload;
      if (metadataPayload != null) {
        metadataComplete = await _recoverMetadata(
          payload: metadataPayload,
          createdWalletRefs: {
            ...defaultCreatedWalletIds,
            ...?keychainResult?.createdWalletIds,
          },
        );
      }

      final keychainComplete =
          keychainError == null &&
          keychainResult != null &&
          switch (keychainResult.status) {
            RemoteKeychainRecoveryStatus.noBackup ||
            RemoteKeychainRecoveryStatus.nothingToRestore ||
            RemoteKeychainRecoveryStatus.restored => true,
            _ => false,
          };
      if (keychainComplete && metadataComplete) {
        final finalIdentityResult = await _walletBackup.fetchRemoteIdentity();
        final WalletBackupRemoteIdentity finalRemoteIdentity;
        switch (finalIdentityResult) {
          case Ok(:final value):
            finalRemoteIdentity = value;
          case Err(:final failure):
            log.warning(
              'Could not revalidate remote wallet backup after recovery',
              error: failure.runtimeType,
            );
            return _withStatus(
              keychainResult,
              RemoteKeychainRecoveryStatus.unavailable,
            );
        }
        if (finalRemoteIdentity != initialRemoteIdentity) {
          log.warning('Remote wallet backup changed during recovery');
          return _withStatus(
            keychainResult,
            RemoteKeychainRecoveryStatus.conflict,
          );
        }
        _requireOk(
          await _walletBackup.setRecoveryBlocked(false),
          'clear recovery block after revalidation',
        );
      } else {
        log.warning(
          'Unified wallet backup recovery remains publication-blocked',
        );
      }
    } finally {
      lease.close();
    }

    if (keychainError != null) {
      Error.throwWithStackTrace(keychainError, keychainStack!);
    }
    if (!metadataComplete) {
      return _withStatus(
        keychainResult!,
        RemoteKeychainRecoveryStatus.partiallyRestored,
      );
    }
    return keychainResult!;
  }

  Future<bool> _recoverMetadata({
    required String payload,
    required Set<String> createdWalletRefs,
  }) async {
    try {
      final result = await _metadataBackup.recoverSection(
        payload: payload,
        createdWalletRefs: Set.unmodifiable(createdWalletRefs),
      );
      if (result case Err(:final failure)) {
        log.warning(
          'Remote wallet metadata recovery failed',
          error: StateError(failure.runtimeType.toString()),
        );
        return false;
      }
      switch (result) {
        case Ok(:final value):
          return value.status == WalletMetadataRecoveryStatus.recovered ||
              value.status == WalletMetadataRecoveryStatus.noSnapshotFound;
        case Err():
          return false;
      }
    } on Exception catch (error, stack) {
      log.warning(
        'Remote wallet metadata recovery threw unexpectedly',
        error: error,
        trace: stack,
      );
      return false;
    }
  }

  T _requireValue<T>(Result<T, WalletBackupFailure> result, String operation) {
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw _WalletBackupRecoveryException(
        '$operation failed: ${failure.runtimeType}',
      ),
    };
  }

  void _requireOk(Result<void, WalletBackupFailure> result, String operation) =>
      _requireValue(result, operation);

  RemoteKeychainRecoveryResult _withStatus(
    RemoteKeychainRecoveryResult result,
    RemoteKeychainRecoveryStatus status,
  ) => RemoteKeychainRecoveryResult(
    status: status,
    restoredCount: result.restoredCount,
    failedCount: result.failedCount,
    createdWalletIds: result.createdWalletIds,
    metadataPayload: result.metadataPayload,
  );
}

final class _WalletBackupRecoveryException implements Exception {
  final String message;

  const _WalletBackupRecoveryException(this.message);

  @override
  String toString() => message;
}
